# IntelliMed on-device app

PBL deliverable, separate from the SE Lab website. Runs SLM prescription/lab
normalization + CNN X-ray pattern inference on-device, syncs structured
results (never raw documents) to the existing backend `/api/v2/*` endpoints.
The website keeps hitting `/api/v1/*` unchanged.

Framing throughout: structured context and pattern flags for doctor review only.

## Layout

- `lib/main.dart` — app shell (Capture / Results / Bench / Spike tabs).
- `lib/cnn_ocr.dart` — ONNX X-ray classifier via `flutter_onnxruntime`
  (fine-tuned ResNet50 bundled at `assets/models/pneumonia_resnet50.onnx`,
  converted from `backend/models/best_model_optimized.pkl`; 224x224 NCHW,
  ImageNet-norm, mirrors `backend/services.py`) + on-device ML Kit OCR.
  Eager vs lazy load is switchable for the responsiveness comparison.
  (`tflite_flutter` stays as the future quantized path.)
- `lib/slm_runtime.dart` — T5 standardizer on ONNX (`OnnxSlmRuntime`,
  same Falconsai checkpoint as the backend) + `t5_tokenizer.dart`
  (SentencePiece port); `llama_cpp_dart` path documented as future-only.
  Decision in `docs/APP_SPIKE.md`.
- `lib/normalize.dart` — deterministic normalizer mirroring the backend
  deterministic-v1 engine; schema-correct JSON for prescriptions + lab reports.
- `lib/schemas.dart` — schema mirrors + validators (reject Stage 3 flags).
- `lib/store.dart` — `sqflite` result store with
  `pending` / `synced` / `failed` sync status.
- `lib/sync.dart` — `/api/v2/*` sync client (`source: "app"`), offline retry,
  connectivity watcher. Never touches `/api/v1/*`.
- `lib/model_manager.dart` — resident model slots + serial `InferenceQueue`.
- `lib/inference_queue.dart` — serial task queue (no overlapping inference).
- Backend counterpart: `POST /api/v2/lab-reports/upload-structured`
  (`backend/api/v2/`) accepts the structured envelopes, re-runs Stage 3
  server-side for lab reports.

## Run

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
# flutter test
# flutter analyze
```

Model files (all tracked under `assets/models/`): the pneumonia ONNX
(regenerated via `backend/scripts/export_pneumonia_onnx.py`) and the
quantized T5 standardizer (`t5_encoder_q8.onnx` + `t5_decoder_q8.onnx` +
`t5_tokenizer.json`, via `backend/scripts/export_t5_summarizer_onnx.py` —
same Falconsai checkpoint the backend uses).

## Open questions (need sign-off, see docs/APP_SPIKE.md)

1. On-device (ML Kit, default) vs server OCR split.
2. Resource arbitration — deferred until `docs/MEMORY_REPORT.md` has numbers.
