# IntelliMed on-device app

Patient app mirroring the website's patient experience, plus on-device
inference. Runs SLM prescription/lab normalization + CNN X-ray pattern
inference on-device; the **Capture** flow syncs structured results (never the
raw image) to `/api/v2/*`. The rest of the app (documents, profile, doctors,
sharing) uses the `/api/v1` patient routes.

Framing throughout: structured context and pattern flags for doctor review only.

## Navigation

Bottom navigation with five destinations (the web app uses a sidebar; the
colour, typography, card and status tokens are shared):

| Tab | What it does |
|---|---|
| **Home** | Counts (reports, documents, captures, pending sync), connected doctors, recent captures |
| **Capture** | On-device inference: pick type (or leave on **Auto**) → camera/gallery/file → normalize → store → sync. Local capture list with per-row sync status |
| **Reports** | Server-side lab reports (`/api/v2`), with a full result viewer |
| **Docs** | Server-side document management: upload, analyse, share, delete |
| **Me** | Profile, notifications, appearance, connected doctors + access code, sign out, developer tools |

### Document types and formats

**Auto** is the default: the app decides the type from the extracted text and
shows what it detected plus the evidence, with a **Change document type**
action that re-runs inference on the stored original (no re-photographing).

Detection order matters. The X-ray head is a *pneumonia* classifier over
`[Normal, Bacterial Pneumonia, Viral Pneumonia]` and has no "not a chest X-ray"
class, so it will happily label a prescription as pneumonia. The app therefore
scores the OCR text first — a printed reference range or a dosing schedule is
decisive — and only consults the classifier for sparse text with no document
markers, requiring its confidence to clear 0.6. That mirrors the backend's
`is_meaningful_xray` guard in `backend/api/patient_router.py`.

Accepted inputs:

| Path | Formats |
|---|---|
| Capture (on-device) | PDF, JPG, JPEG, PNG, WebP, BMP, TIF, TIFF |
| Docs (server upload) | PDF, JPG, JPEG, PNG, BMP, TIF, TIFF |

PDF pages are rasterized on-device (`pdfx`, the platform renderer) at ~200 DPI,
OCR'd in page order, and normalized as **one** document rather than one capture
per page — a multi-page lab report has its panels spread across pages. Up to
`maxPdfPages` (12) pages are processed; a longer document records
`pages_truncated` in the envelope so a reviewer can see the cap applied.

HEIC/HEIF is deliberately not offered: the Dart `image` package cannot decode
it, so the X-ray path would fail after the photo was taken.

### Raw documents

**Docs** uploads original files (`POST /api/v1/patient/upload/`), matching the
website: the backend stores them and runs OCR/CV/NLP/T5. This is the only path
that sends raw documents, it is always an explicit user action, and it never
happens automatically. **Capture** stays structured-results-only — it reads the
file locally and syncs just the structured envelope.

## Layout

- `lib/main.dart` — entry point; builds auth, the shared API client, the
  repository and the theme controller, then gates on sign-in.
- `lib/app_shell.dart` — bottom-nav shell over the five screens.
- `lib/api/` — `api_client.dart` (one HTTP layer: bearer token, timeouts,
  multipart, error mapping, single silent 401 refresh), `models.dart`
  (defensive parsers for all result envelope shapes), `patient_repository.dart`.
- `lib/screens/` — `home`, `capture`, `capture_detail`, `reports`,
  `report_detail`, `documents`, `document_detail`, `profile`.
- `lib/document_type.dart` — on-device document-type detection. Scores OCR text
  for lab vs prescription evidence and only falls back to the X-ray classifier
  for sparse, marker-free text (see "Document types" above). Also records the
  evidence in the envelope for the reviewing doctor.
- `lib/page_source.dart` — file ingest. Turns any supported file into page
  images: images pass through, PDFs are rasterized via `pdfx`. Owns the
  per-format allow-lists and keeps a durable copy of each capture's source so a
  capture can be re-run later.
- `lib/widgets/` — `app_card`, `app_bottom_nav`, `stat_card`, `feedback`
  (empty/error/loading/banner), `filter_chips`, `result_viewers`,
  `confirm_dialog`, `brand_mark`, `status_chip`.
- `lib/auth.dart` — Google sign-in → backend JWT exchange, Keystore-backed
  token storage, silent refresh, sign-out.
- `lib/theme_controller.dart` — persisted light/dark/system choice.
- `lib/cnn_ocr.dart` — ONNX X-ray classifier via `flutter_onnxruntime`
  (fine-tuned ResNet50 bundled at `assets/models/pneumonia_resnet50.onnx`,
  converted from `backend/models/best_model_optimized.pkl`; 224x224 NCHW,
  ImageNet-norm, mirrors `backend/services.py`) + on-device ML Kit OCR.
  Eager vs lazy load is switchable for the responsiveness comparison.
  (`tflite_flutter` stays as the future quantized path.)
- `lib/slm_runtime.dart` — Qwen3-0.6B (Q4_0 GGUF) via `llama_cpp_dart`: the
  on-device summariser/explainer behind every capture summary and AI insight.
  It compresses/explains text and never emits structure (the interface has no
  JSON entry point). Fetched with `tool/download_qwen3_gguf.ps1`; active-model
  notes in `docs/APP_SPIKE.md`.
- `lib/patient_summary.dart` + `lib/screens/patient_summary_screen.dart` — the
  doctor hand-off: every stored prescription/lab report reduced to deterministic
  facts plus one on-device model pass (map -> reduce). Reached from Home.
- `lib/lab/` — the on-device lab pipeline: `ocr_model.dart` (ML Kit geometry),
  `structure.dart` (geometry -> backend-compatible Stage 1), `rule_engine.dart`
  (ported deterministic Stage 2, parity-tested against the Python reference),
  `extract.dart` (structural result + a flat-text recovery pass, so a
  mis-guessed table can never extract fewer values than the old per-line
  parser), `pdf_text.dart` + `pdf_geometry.dart` (read a digital PDF's **exact
  text layer** via pdfrx/pdfium instead of OCR-ing a render), plus
  `test_names.dart` and `render.dart`. The envelope's `structure` block reports
  `source` (`pdf-text` | `ocr`) and `recovered` (rows only recovery found).
- `lib/normalize.dart` — deterministic prescription normalizer + the shared
  result-envelope builder. Lab reports no longer go through a flat-text regex.
- `lib/capture_quality.dart` — pre-inference capture quality gate (blur =
  variance of Laplacian, glare = clipped-white fraction, darkness), plus a
  post-OCR small-text check. Deterministic pixel statistics, no model.
- `lib/trends.dart` — longitudinal trends over stored rows: one unit-consistent
  series per canonical test name + unit, reference bands, and a local/server
  merge that does not double-count a synced capture.
- `lib/widgets/trend_sparkline.dart` — dependency-free `CustomPainter` sparkline
  with the printed reference band shaded.
- `lib/screens/trends_screen.dart` / `trend_detail_screen.dart` — "your values
  over time", reached from Home and Reports. Wording is descriptive only.
- Capture uses `google_mlkit_document_scanner` (Android-only: edge detection,
  perspective correction, dewarp) replacing the raw camera path; gallery and
  file picks pass through the same quality gate. A page ML Kit reports as
  skewed is rotated and re-OCR'd (`cnn_ocr.dart`) rather than losing all table
  structure.
- `lib/schemas.dart` — schema mirrors + validators (reject Stage 3 flags).
- `lib/store.dart` — `sqflite` result store with
  `pending` / `synced` / `failed` sync status.
- `lib/sync.dart` — `/api/v2/*` structured-result sync client (`source: "app"`),
  offline retry, connectivity watcher. Only this file's traffic is v2;
  everything else the app calls is `/api/v1`.
- `lib/model_manager.dart` — resident model slots + serial `InferenceQueue`.
- `lib/inference_queue.dart` — serial task queue (no overlapping inference).
- `lib/login_screen.dart` — sign-in screen (web-matching design tokens).
- `lib/tabs_bench_spike.dart` — Bench/Spike measurement harnesses, reached
  from Me → Developer rather than a primary nav slot.
- `lib/copy.dart` — non-diagnostic wording rules for every screen.
- Backend counterpart (`backend/api/v2/lab_report_router.py`):
  `POST /api/v2/lab-reports/upload-structured` accepts the structured envelopes
  and re-runs Stage 3 server-side; `POST /api/v2/lab-reports/upload` runs the
  full Stage 1-3 pipeline on a raw file (used by Docs → "Lab report");
  `GET /api/v2/lab-reports/{id}` reads one; `DELETE /api/v2/lab-reports/{id}`
  removes the patient's own report and any stored file.

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

## Device testing

The app talks to one backend base URL (`API_BASE_URL`), which must be the
**origin only** — it appends `/api/v2/...` and `/api/v1/...` itself.

```bash
# .env  (gitignored) — deployed backend, reachable from any network
API_BASE_URL=https://sarthak-routray2006--intellimed-backend.modal.run
```

```bash
flutter devices                     # confirm the phone is attached
flutter run --dart-define-from-file=.env
```

### Which URL to use

| Target | API_BASE_URL |
|---|---|
| Physical device, deployed backend | `https://<your-app>.modal.run` |
| Physical device, backend on your PC | `http://<your-LAN-IP>:8000` |
| Android emulator | `http://10.0.2.2:8000` |
| iOS simulator | `http://localhost:8000` |

Plain `http://` works in **debug builds only** — debug builds enable cleartext
traffic via `android/app/src/debug/AndroidManifest.xml`. Release builds are
HTTPS-only, so the deployed backend needs no exception.

### Verifying the connection on-device

Open the **Bench** tab and run the harness. The report ends with:

```
online=true|false
backend=<the URL this build is actually using>
auth=token set | no token (sign in required)
```

If sync fails, check `backend` first — a wrong `API_BASE_URL` is the most common
cause. Note the deployed backend requires a valid patient JWT; the v2 ingest
route returns `401 Not authenticated` without one.

### If Google sign-in isn't working yet

Google sign-in has external prerequisites (consent screen configured, your
account added as a test user, the debug SHA-1 registered as an Android OAuth
client). To device-test the capture/sync path without them, bypass OAuth with a
patient JWT:

```bash
# 1. Register a patient (or skip if you already have one)
curl -X POST https://<your-app>.modal.run/api/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","password":"<pw>","name":"Test","role":"patient"}'

# 2. Log in to get the JWT (OAuth2 password form, not JSON)
curl -X POST https://<your-app>.modal.run/api/v1/auth/token \
  -d "username=you@example.com&password=<pw>"
```

Put the returned `access_token` in `.env` as `AUTH_TOKEN=...`. The app uses it
directly and skips the Google flow. Tokens expire after 30 minutes; if sync
starts returning 401, fetch a fresh one (queued captures stay `pending`, so
nothing is lost).

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

Model files: the pneumonia ONNX under `assets/models/` is tracked (regenerated
via `backend/scripts/export_pneumonia_onnx.py`). The SLM GGUF
(`assets/models/Qwen3-0.6B-Q4_0.gguf`, ~364 MB) is **not** committed — fetch it
with `mobile/tool/download_qwen3_gguf.ps1`.

## Open questions (need sign-off, see docs/APP_SPIKE.md)

1. On-device (ML Kit, default) vs server OCR split.
2. Resource arbitration — deferred until `docs/MEMORY_REPORT.md` has numbers.
