# IntelliMed on-device app

PBL deliverable, separate from the SE Lab website. Runs SLM prescription/lab
normalization + CNN X-ray pattern inference on-device, syncs structured
results (never raw documents) to the existing backend `/api/v2/*` endpoints.
The website keeps hitting `/api/v1/*` unchanged.

Framing throughout: structured context and pattern flags for doctor review only.

## Layout

- `lib/main.dart` — app shell (Capture / Results / Bench / Spike tabs), gated
  on Google sign-in state.
- `lib/auth.dart` — Google sign-in → backend JWT exchange, Keystore-backed
  token storage, silent refresh, sign-out. Pure JWT `exp` helpers.
- `lib/login_screen.dart` — sign-in screen (web-matching design tokens).
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

Create your local config first (it is gitignored and holds real client IDs):

```bash
cd mobile
flutter pub get
copy .env.example .env      # then fill in GOOGLE_WEB_CLIENT_ID
```

Run against the backend (Android emulator uses `10.0.2.2` for host localhost):

```bash
flutter run --dart-define-from-file=.env
# flutter test
# flutter analyze
```

Flutter does **not** auto-load `.env`. It must be applied explicitly with
`--dart-define-from-file=.env` (also accepted: a `.json` file). Values passed
inline with `--dart-define=` take precedence over the file.

## Sign-in

The app signs in with Google and exchanges the Google ID token for a backend
JWT at `POST /api/v1/auth/google-login`, then stores the JWT in
Keystore-backed encrypted storage. This is the app's **only** `/api/v1` call —
inference and result upload stay on `/api/v2/*`. With a signed-in session,
captures work offline and sync automatically on reconnect.

The app is **patient-only**: `/api/v2/lab-reports/upload-structured` rejects
other roles, so a doctor account cannot sync captures.

### Google Cloud setup

Three things must exist in the same Google Cloud project as the backend's
`GOOGLE_CLIENT_ID`:

1. **An Android OAuth client** — registered with the package name
   `ai.intellimed.intellimed_app` and the signing SHA-1. It is *registration
   only* and never appears in code or env.
   - Debug SHA-1: `keytool -list -v -keystore %USERPROFILE%\.android\debug.keystore
     -alias androiddebugkey -storepass android -keypass android`
2. **A configured OAuth consent screen** (app name + support email).
3. While the app is in **Testing**, your Google account added as a **test user**
   — otherwise sign-in fails with no useful error.

### Which client ID goes where

| ID | Used for |
|---|---|
| Android client | Registered in GCP only (package + SHA-1) — never in code |
| **Web** client | `GOOGLE_WEB_CLIENT_ID` → passed as `serverClientId` |

`serverClientId` **must** be the web client ID. On Android it is required, and
passing the Android client instead raises
`GoogleSignInExceptionCode.clientConfigurationError`. The web client is also
what the backend validates against (`GOOGLE_CLIENT_ID`), so the returned
idToken's audience matches.

Set the web client ID in your gitignored `.env` (see `.env.example` for the
full template), or override it inline:

```bash
flutter run --dart-define-from-file=.env \
            --dart-define=GOOGLE_WEB_CLIENT_ID=<web-client-id>
```

There is no built-in default — an unset `GOOGLE_WEB_CLIENT_ID` makes sign-in
report a configuration error rather than failing silently.

`AUTH_TOKEN` still exists as an emulator-only escape hatch that bypasses OAuth;
Google sign-in is the normal path.

No `google-services.json` is required — that is Firebase, not `google_sign_in`.

Model files (all tracked under `assets/models/`): the pneumonia ONNX
(regenerated via `backend/scripts/export_pneumonia_onnx.py`) and the
quantized T5 standardizer (`t5_encoder_q8.onnx` + `t5_decoder_q8.onnx` +
`t5_tokenizer.json`, via `backend/scripts/export_t5_summarizer_onnx.py` —
same Falconsai checkpoint the backend uses).

## Open questions (need sign-off, see docs/APP_SPIKE.md)

1. On-device (ML Kit, default) vs server OCR split.
2. Resource arbitration — deferred until `docs/MEMORY_REPORT.md` has numbers.
