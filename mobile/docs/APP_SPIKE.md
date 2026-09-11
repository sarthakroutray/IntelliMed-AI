# IntelliMed On-Device App — model wiring & open questions

## 0. CNN: WIRED (this session)

- **Source found in workspace:** `backend/models/best_model_optimized.pkl`
  (90 MB, torch `state_dict`, ResNet50 + Dropout(0.3) + Linear(2048 -> 3)).
- **Conversion:** `backend/scripts/export_pneumonia_onnx.py` rebuilds the
  exact head from `backend/services.py`, loads the checkpoint, exports opset
  18 ONNX. Verified: `onnx.checker` OK (122 nodes), `onnxruntime` CPU run OK
  with `(1, 3)` logits output; checkpoint forward pass sane.
- **Bundled artifact:** `mobile/assets/models/pneumonia_resnet50.onnx`
  (~94 MB single-file, tracked in git as a build artifact of the `.pkl`).
- **Runtime:** `flutter_onnxruntime` (`CnnClassifier`, NCHW `[1,3,224,224]`
  float input, same ImageNet mean/std + labels as the backend). Eager vs
  lazy load still switchable; Bench tab times both.
- **TFLite status:** deferred — TF install kept timing out on this machine,
  and the ONNX path already gives real on-device inference with the same
  weights. `tflite_flutter` stays in pubspec; select it later with
  `--dart-define=CNN_BACKEND=tflite` once `xray_cnn.tflite` is converted.

## 1. SLM: WIRED — the previous standardizer (this session)

You were right: git history shows the "SLM" was never a separate file — it
is the Falconsai T5 summarizer the backend has used since `622ce60` as its
OCR text standardizer (`medical_summarize_service` in `backend/services.py`,
still called by both routers today). Same checkpoint, now on-device:

- **Source:** `Falconsai/medical_summarization` (T5-small, 60M params —
  this is the "~80M-class" standardizer role).
- **Conversion:** `backend/scripts/export_t5_summarizer_onnx.py` (optimum
  exporter, legacy tracer — torch dynamo exporter cannot handle T5
  attention reshapes). Verified: `onnx.checker` OK on both graphs,
  6-token greedy prefix matches HF `generate` exactly (fp32 and int8).
- **Quantized artifacts (tracked):** `mobile/assets/models/t5_encoder_q8.onnx`
  (35.5 MB) + `t5_decoder_q8.onnx` (58.5 MB) — 374 MB fp32 → ~94 MB int8 —
  plus `t5_tokenizer.json` (2.4 MB).
- **Runtime:** `OnnxSlmRuntime` (encoder once + autoregressive greedy decode
  via `flutter_onnxruntime`) + `t5_tokenizer.dart` (SentencePiece-Unigram
  Viterbi port, parity-pinned: exact match on 3 HF reference vectors).
- **Role in the pipeline** (`ModelManager.processDocument`): deterministic
  schema normalization always runs; the T5 standardizer adds
  `summary_context: {medical_summary, ...}` on non-prescription documents —
  mirroring the backend, where prescriptions short-circuit to structured
  NLP data and never go through the generative path.
- **Known T5 behavior (measured, not a bug in the port):** the checkpoint
  loops/repeats on short lab-value strings ("glucose 98 mg/dL, a glucose
  98 mg/dL, ...") and mostly echoes prescriptions. It behaves as a
  prose standardizer, matching its backend role; schema extraction stays
  deterministic. If schema-grade generative normalization is needed later,
  that is a fine-tune task, not a porting task.

## 2. llama_cpp_dart vs ONNX — decision (made, this session)

- **Decision: ONNX via `flutter_onnxruntime` — no GGUF path.** There is no
  GGUF file anywhere (workspace, history, LFS, HF cache) because the
  standardizer was always this T5 checkpoint, which exports cleanly to ONNX.
  `llama_cpp_dart` stays in pubspec as a listed dependency but
  `LlamaCppRuntime` is explicitly unwired; `EAGER_MODEL_LOAD` now loads the
  T5 path.

## 3. On-device vs server OCR for this app

- **Default in this app: on-device OCR via `google_mlkit_text_recognition`
  (ML Kit Latin script).** Rationale: works offline, keeps the offline-queue
  story coherent (capture → OCR → normalize → queue → sync with no network),
  no extra backend call, matches Android-first scope.
- **Tradeoff flagged:** ML Kit gives text lines, not the table structure +
  bounding boxes the backend Stage 1 (OpenDataLoader) produces. Mitigation:
  the deterministic normalizer marks table-missed rows `ocr_confidence:
  "low"` and the structured envelope carries an `ocr_excerpt`; the backend
  re-runs Stage 3 rules server-side on ingest.
- **Server OCR stays available** via `POST /api/v2/lab-reports/upload`
  (file upload + full pipeline) for scanned/table-heavy cases the on-device
  pass marks low-confidence. Needs your confirmation that this split is
  acceptable for the PBL scope.

## 4. Resource arbitration: needed or not?

- **Current position: NOT needed — do not build it.** Both models stay
  loaded and resident (`ModelManager`, eager-load opt-in via
  `--dart-define=EAGER_MODEL_LOAD=true`). A serial `InferenceQueue`
  prevents overlapping calls competing for the same resources.
- **Gate before any swap-in/swap-out work:** real combined-footprint +
  latency numbers from the Bench tab on a mid-range device, recorded in
  `docs/MEMORY_REPORT.md`. Only if resident memory causes pressure do we
  add lazy/evict logic.
