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

## 1. SLM: WIRED — the T5 summariser, not a structurer (this session)

Git history shows the "SLM" was never a separate file — it is the Falconsai
T5 summarizer the backend has used since `622ce60` as its OCR-text summariser
(`medical_summarize_service` in `backend/services.py`, still called by both
routers today). Same checkpoint, now on-device:

- **Source:** `Falconsai/medical_summarization` (T5-small, 60M params —
  this is the "~80M-class" summariser role).
- **Conversion:** `backend/scripts/export_t5_summarizer_onnx.py` (optimum
  exporter, legacy tracer — torch dynamo exporter cannot handle T5
  attention reshapes). Verified: `onnx.checker` OK on both graphs,
  6-token greedy prefix matches HF `generate` exactly (fp32 and int8).
- **Quantized artifacts (tracked):** `mobile/assets/models/t5_encoder_q8.onnx`
  (35.5 MB) + `t5_decoder_q8.onnx` (58.5 MB) — 374 MB fp32 → ~94 MB int8 —
  plus `t5_tokenizer.json` (2.4 MB).
- **Runtime:** `OnnxSummarizer` (encoder once + autoregressive greedy decode
  via `flutter_onnxruntime`) + `t5_tokenizer.dart` (SentencePiece-Unigram
  Viterbi port, parity-pinned: exact match on 3 HF reference vectors).
- **Role in the pipeline** (`ModelManager.processDocument`): lab structure
  comes from the on-device rule engine (see section 1a); the T5 summariser
  only adds `summary_context: {medical_summary, ...}` on non-prescription
  documents. It is fed the *rendered structure* (`renderLabText`), not the
  raw OCR stream. Mirrors the backend, where prescriptions short-circuit to
  structured NLP data and never go through the generative path.
- **Known T5 behavior (measured, not a bug in the port):** the checkpoint
  loops/repeats on short lab-value strings ("glucose 98 mg/dL, a glucose
  98 mg/dL, ...") and mostly echoes prescriptions. It behaves as a prose
  summariser, matching its backend role. If schema-grade generative
  normalization is needed later, that is a fine-tune task, not a porting task.

## 1a. Lab structure: rule engine on-device

Lab structure is not an SLM job. The on-device path is now:

    ML Kit geometry -> OcrPage (lib/lab/ocr_model.dart)
      -> structure.dart -> Stage 1 (elements + tables/rows/cells)
      -> rule_engine.dart (ported from backend/lab_pipeline/slm_stage.py)
      -> the fixed 10-key test schema
      -> renderLabText -> T5 summarize() (summary_context only)

- `lib/lab/structure.dart` synthesises the backend's Stage 1 shape from word
  boxes: grid-like line detection, column clustering, row/cell assembly,
  merged-line re-splitting and wrapped-value attachment. Rotated pages and
  pages without geometry degrade explicitly (`mlkit-lines-only`) rather than
  guessing columns.
- `lib/lab/rule_engine.dart` is a faithful port of `_build_document` and
  friends. It emits exactly the 10 required keys and never `abnormal` /
  `direction` — Stage 3 stays server-side.
- Parity is enforced by `mobile/test/lab_rule_engine_test.dart`: the Dart
  engine must equal the Python reference's output for every fixture in
  `mobile/test/fixtures/lab/`. Regenerate the goldens with
  `python backend/scripts/run_stage2_fixture.py <fixture>`.

## 2. llama_cpp_dart vs ONNX — decision (made, this session)

- **Decision: ONNX via `flutter_onnxruntime` — no GGUF path.** There is no
  GGUF file anywhere (workspace, history, LFS, HF cache) because the
  summariser was always this T5 checkpoint, which exports cleanly to ONNX.
  `llama_cpp_dart` stays in pubspec as a listed dependency but
  `LlamaCppRuntime` is explicitly unwired; `EAGER_MODEL_LOAD` now loads the
  T5 path.

## 3. On-device vs server OCR for this app

- **Default in this app: on-device OCR via `google_mlkit_text_recognition`
  (ML Kit Latin script).** Rationale: works offline, keeps the offline-queue
  story coherent (capture → OCR → normalize → queue → sync with no network),
  no extra backend call, matches Android-first scope.
- **Tradeoff flagged (updated):** ML Kit's flat text discarded the table
  structure the backend Stage 1 (OpenDataLoader) provides. The app now keeps
  ML Kit's word boxes and reconstructs Stage 1 on-device (section 1a), so
  table-missed rows are still recovered at `ocr_confidence: "low"` and the
  envelope carries an `ocr_excerpt` plus a `structure` provenance block. The
  backend still re-runs Stage 3 rules server-side on ingest.
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

## 5. Qwen3-0.6B SLM (this session)

- **Qwen3-0.6B (Q3_K_S GGUF) is now the active SLM**, replacing the T5-small
  ONNX summariser as the `MedicalSummarizer` implementation. It produces the
  capture-path `summary_context` (engine suffix `+qwen-summary`) and powers the
  new insight tasks. `OnnxSummarizer` + `t5_tokenizer.dart` are retained but
  `@Deprecated` for A/B comparison and rollback.
- **Insight tasks** (`QwenSlmRuntime.explainBiomarker`, `doctorVisitPrep`,
  `translateInstructions`) are reached through `ModelManager.runInsightTask`,
  which serialises on the shared `InferenceQueue` and loads the model lazily.
  They surface in the capture detail screen (`widgets/insight_card.dart`):
  per-value explanations, three doctor-visit questions, and Hindi/Spanish
  instruction translation for prescriptions.
- **No parallel clinical engine.** Explanations only describe values that
  `lab/clinical_engine.dart` already flagged (`is_panic_value`,
  `abnormal`/`direction`); flagging and panic detection stay deterministic.
  The SLM never emits a flag or verdict.
- **Thinking mode**: ON for explanations and visit prep, OFF (`/no_think`) for
  summary and translation. Output length varies run to run, so `_complete`
  retries once without thinking if the `<think>` block never closes.

### Deployment requirements (verified, not assumed)

- **Native llama.cpp libraries — checked in** under
  `mobile/android/app/src/main/jniLibs/arm64-v8a/`: `libmtmd.so`, `libllama.so`,
  `libggml.so`, `libggml-cpu.so`, `libggml-base.so`, `libomp.so`,
  `libc++_shared.so` (~6 MB stripped, 16 KB-page aligned). Built from llama.cpp
  at commit `4ffc47cb` — the revision pinned by `llama_cpp_dart` 0.2.2, so the
  FFI bindings match its headers. Rebuild with
  `pwsh mobile/tool/build_llama_android.ps1` (add `-Abi x86_64` for an
  emulator). `libggml-cpu.so` links the OpenMP runtime and `libllama.so` links
  `libc++_shared`, so both must ship or `dlopen("libmtmd.so")` fails.
- **GGUF model** at `assets/models/Qwen3-0.6B-Q3_K_S.gguf` (~372 MB,
  gitignored); fetch with `pwsh mobile/tool/download_qwen3_gguf.ps1`. Header
  verified: GGUF v3, 311 tensors, `general.architecture = qwen3`, 28 blocks /
  1024 hidden / 16 heads, 4168-char chat template, `eos_token_id = 151645`.

### Runtime gotchas (probed against llama_cpp_dart 0.2.2 and llama.cpp)

- **`ModelParams.mainGpu` must be `-1` on a CPU-only build.** llama.cpp builds
  its device list from GPU/IGPU/RPC devices only; with no GPU backend the list
  is empty and the default `main_gpu = 0` fails the range check in
  `llama_model_load_from_file_impl` with
  `invalid value for main_gpu: 0 (available devices: 0)`.
  `nGpuLayers = 0` alone does not avoid it.
- `LlamaLoad` has no `format:` field; prompts are built by hand
  (`buildChatMlPrompt`) because `ChatMLFormat` re-wraps whatever it is given.
- Completion is awaited via `waitForCompletion(promptId)`; there is no
  empty-string stream sentinel.
- llama.cpp needs a real file path, so a bundled asset key is extracted once
  to application support storage (atomically) before loading.
- `verbose: true` is inert on Android: the package never wires its Dart log
  callback and llama.cpp's logger writes to stderr, which the platform drops.
  Native errors require capturing logcat after temporarily installing
  `llamaLogCallbackPrint`.

### Measured on-device (Galaxy S23, arm64-v8a, Android 16)

- Qwen3-0.6B Q3_K_S load: **~3–4 s** (28-layer CPU context, 224 MiB f16 KV).
- `explainBiomarker` (thinking): **13–38 s**, dominated by the think block.
- First use extracts ~372 MB out of the APK.
