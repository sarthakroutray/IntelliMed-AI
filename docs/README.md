# IntelliMed-AI

IntelliMed-AI is a full-stack medical document platform that connects patients and doctors with secure sharing and AI-assisted analysis.

The system supports:
- Role-based authentication (patient, doctor, admin)
- Patient-doctor linking with access codes
- Medical document upload, sharing, review, and archival
- AI pipelines for OCR, medical NLP extraction, and chest X-ray classification
- Lab report understanding pipeline (v2) with traceable, rule-based flagging
- On-device Flutter app (Android-first) with the same patient feature set as the web app

API versioning: the website uses `/api/v1/*` (frozen contract); the mobile
app uses `/api/v2/*` for structured results and the `/api/v1` patient routes
for documents, profile, doctors and sharing. Doctor-side verification happens
on the backend/dashboard; the app supports the patient side of the workflow.

The app runs OCR and normalization on-device and syncs the structured result
(never the raw image) for the **Capture** flow. It can also upload original
documents from **Docs**, matching the website — those uploads are always an
explicit user action and are stored server-side.

## 1. Project Overview

### Problem Statement
Healthcare workflows often involve fragmented document handling, delayed specialist access, and unstructured records that are difficult to interpret quickly.

### Solution
IntelliMed-AI provides a centralized application where patients can upload medical files and authorized doctors can review them with AI-generated insights.

### Objectives
- Improve accessibility of medical records between patient and doctor
- Reduce manual review time using AI-assisted extraction and classification
- Maintain secure, role-aware access control to sensitive data

## 2. Key Features

### User and Access Management
- JWT-based authentication
- Google OAuth login support
- Role-based route protection (patient/doctor/admin)
- Optional controlled doctor onboarding via access code

### Patient Workflow
- Upload medical documents
- View document history
- Share/unshare specific documents with linked doctors
- Trigger AI analysis per document

### Doctor Workflow
- Link to patients using patient-generated access code
- View linked patient documents
- Review AI analysis output
- Verify analysis and add clinical notes

### Document Lifecycle
- Upload -> Analyze -> Review -> Verify -> Archive
- Secure document retrieval and controlled sharing

## 3. AI Capabilities

### OCR Pipeline
- Multi-pass OCR strategy with preprocessing
- Handles scanned/low-quality prescription-like images
- Uses Tesseract + optional EasyOCR fallback patterns
- Includes optional OpenDataLoader integration for PDFs

### Medical NLP Extraction
- Extracts medication-related entities and prescription-like patterns
- Detects dosage/frequency/duration-like tokens where present
- Uses spaCy when available, with fallback behavior for robustness

### Chest X-Ray Analysis
- ResNet50-based classifier (fine-tuned; `backend/models/best_model_optimized.pkl`)
- Classes: Normal, Bacterial Pneumonia, Viral Pneumonia
- Returns probabilities and a primary classification label
- On-device twin: converted to `mobile/assets/models/pneumonia_resnet50.onnx`
  via `backend/scripts/export_pneumonia_onnx.py`, run with flutter_onnxruntime

### Lab Report Understanding (v2)
- Stage 1: OpenDataLoader extraction with bounding boxes (EasyOCR fallback)
- Stage 2: deterministic normalization, optional SLM via OpenAI-compatible hook
- Stage 3: deterministic rule engine (`backend/lab_pipeline/`, external `rules.json`)
- Endpoints under `/api/v2` (upload + patient/doctor reads + structured ingest)

### Medical Text Standardizer (shared backend/app checkpoint)
- Falconsai T5 summarizer (`Falconsai/medical_summarization`, T5-small 60M)
  behind `medical_summarize_service` for non-prescription documents
- On-device twin: quantized encoder/decoder ONNX
  (`mobile/assets/models/t5_encoder_q8.onnx` + `t5_decoder_q8.onnx`, ~94 MB int8)
  via `backend/scripts/export_t5_summarizer_onnx.py`, with a Dart
  SentencePiece port (`mobile/lib/t5_tokenizer.dart`) parity-pinned to HF vectors

## 4. Architecture

### Backend
- FastAPI application in backend/
- Prisma ORM with PostgreSQL
- In-memory API caching (fastapi-cache2)
- Supabase storage integration for medical files

### Frontend
- React + Vite single-page app in frontend/
- React Router based navigation
- Axios API client and auth context

### Data Model (Prisma)
Core entities include:
- User
- DoctorPatient
- MedicalDocument (with `source` tag: `web` | `app`)
- LabReport (v2 pipeline results, with `source` tag)
- DocumentShare

Schema file:
- backend/prisma/schema.prisma

## 5. Tech Stack

### Backend
- FastAPI
- Prisma Client Python
- PostgreSQL
- python-jose + passlib for auth/security
- Supabase SDK

### AI/ML
- PyTorch + torchvision
- OpenCV
- pytesseract
- spaCy
- Pillow
- NumPy
- transformers + sentencepiece (Falconsai T5 summarizer)
- onnx / onnxruntime + optimum (model export + parity checks)

### Mobile (mobile/)
- Flutter 3.44 / Dart 3.12, Android-first (minSdk 26)
- flutter_onnxruntime (X-ray ResNet50 + T5 summarizer, on-device)
- on-device lab rule engine (ML Kit geometry -> Stage 1 -> ported Stage 2)
- google_mlkit_text_recognition (on-device OCR), image_picker (capture)
- sqflite (result store: pending/synced/failed), connectivity_plus + http (v2 sync)

### Frontend
- React 18
- Vite
- React Router DOM
- Axios
- TailwindCSS (configured in dependencies)

## 6. Repository Structure

```text
.
├─ backend/
│  ├─ api/
│  │  ├─ v2/                     (lab report understanding + structured ingest)
│  ├─ lab_pipeline/              (OCR stage, SLM/deterministic stage, rule engine)
│  ├─ scripts/                   (ONNX export + SLM fine-tune dataset prep)
│  ├─ tests/                     (rule engine + ingest schema tests)
│  ├─ prisma/
│  ├─ models/                    (checkpoints; converted artifacts via LFS)
│  ├─ main.py
│  ├─ services.py
│  └─ requirements.txt
├─ mobile/                       (on-device Flutter app, Android-first)
│  ├─ lib/                       (CNN, T5 runtime + tokenizer, store, sync)
│  ├─ assets/models/             (tracked ONNX artifacts)
│  ├─ test/                      (tokenizer parity, normalization, queue tests)
│  └─ docs/                      (APP_SPIKE.md decision log, MEMORY_REPORT.md)
├─ frontend/
│  ├─ src/
│  │  ├─ components/
│  │  ├─ context/
│  │  ├─ pages/
│  │  ├─ services/
│  │  └─ styles/
│  ├─ package.json
│  └─ vite.config.js
├─ docker-compose.yml
├─ DEPLOYMENT.md
└─ test_ai_services.py
```

## 7. Local Development Setup

### Prerequisites
- Python 3.10+
- Node.js 18+
- PostgreSQL database

### Backend Setup

```bash
cd backend
python -m venv venv
# Windows
venv\Scripts\activate
# macOS/Linux
# source venv/bin/activate

pip install -r requirements.txt
```

Create backend env file:

```bash
copy .env.example .env
```

Required values to set in backend/.env:
- DATABASE_URL
- DIRECT_URL
- SECRET_KEY
- GOOGLE_CLIENT_ID
- SUPABASE_URL
- SUPABASE_SERVICE_KEY
- SUPABASE_STORAGE_BUCKET

Generate Prisma client and sync database schema:

```bash
prisma generate
prisma db push
```

Run backend:

```bash
uvicorn main:app --reload --port 8000
```

API docs:
- http://localhost:8000/docs

### Frontend Setup

```bash
cd frontend
npm install
```

Create frontend env file:

```bash
copy .env.example .env
```

Run frontend:

```bash
npm run dev
```

App URL:
- http://localhost:5173

### Mobile App Setup

```bash
cd mobile
flutter pub get
copy .env.example .env      # then fill in GOOGLE_WEB_CLIENT_ID
```

Run (Android emulator uses `10.0.2.2` for host localhost):

```bash
flutter run --dart-define-from-file=.env
```

Flutter does not auto-load `.env`; it must be applied with
`--dart-define-from-file=.env`. The real `.env` is gitignored.

The app signs in with Google (patient-only) and exchanges the ID token for a
backend JWT at `/api/v1/auth/google-login`, then stores it in Keystore-backed
encrypted storage. That is the app's only v1 call; inference and upload stay on
v2. `GOOGLE_WEB_CLIENT_ID` (the **web** client ID, used as `serverClientId`)
has no built-in default; `AUTH_TOKEN` remains an emulator-only OAuth bypass.
See `mobile/README.md` for the required Google Cloud setup.

Model assets are already tracked under `mobile/assets/models/` (LFS):
pneumonia ResNet50 ONNX + quantized T5 encoder/decoder + tokenizer.

Validate:

```bash
flutter test
flutter analyze
```

Details: `mobile/README.md`, decision log `mobile/docs/APP_SPIKE.md`,
measurement gate `mobile/docs/MEMORY_REPORT.md`.

## 8. Docker Setup

Run both services:

```bash
docker compose up --build
```

Compose file:
- docker-compose.yml

## 9. Environment Variables Reference

### backend/.env
- GOOGLE_CLIENT_ID
- CORS_ORIGINS
- CORS_ORIGIN_REGEX
- SUPABASE_URL
- SUPABASE_SERVICE_KEY
- SUPABASE_STORAGE_BUCKET
- SUPABASE_SIGNED_URL_EXPIRES_SECONDS
- MAX_UPLOAD_SIZE_MB
- CACHE_TTL_SECONDS
- DATABASE_URL
- DIRECT_URL
- SECRET_KEY
- DOCTOR_ACCESS_CODE
- ADMIN_EMAIL
- ADMIN_PASSWORD
- MAX_CONCURRENT_HEAVY
- AUTH_USER_CACHE_TTL_SECONDS / DOCTOR_PATIENT_CACHE_TTL_SECONDS / REQUEST_CACHE_MAX_ENTRIES
- USE_OPENDATALOADER_FOR_PDFS / OPENDATALOADER_USE_STRUCT_TREE / OPENDATALOADER_HYBRID (+ URL/TIMEOUT)
- LAB_OPENDATALOADER_HYBRID (+ MODE/URL/TIMEOUT)
- LAB_MIN_EXTRACT_TEXT_CHARS
- LAB_SLM_PROVIDER (+ URL/MODEL/API_KEY; empty = deterministic normalizer)
- MEDICAL_SUMMARIZER_MODEL / SUMMARY_MAX_LENGTH / SUMMARY_MIN_LENGTH / SUMMARIZER_MAX_INPUT_CHARS

### frontend/.env
- VITE_API_BASE_URL (must end in `/api/v1`; the client appends it if missing)
- VITE_GOOGLE_CLIENT_ID

### mobile (dart-defines; copy `.env.example` to `.env`)
Applied with `flutter run --dart-define-from-file=.env` (Flutter does not
auto-load `.env`). The real `.env` is gitignored.
- API_BASE_URL (backend origin only, no `/api` suffix; emulator `10.0.2.2`)
- GOOGLE_WEB_CLIENT_ID (web OAuth client ID, used as `serverClientId`; no default)
- AUTH_TOKEN (optional emulator-only OAuth bypass)
- CNN_MODEL_ASSET / SLM_GGUF_ASSET / EAGER_MODEL_LOAD / CNN_BACKEND

### root .env (docker compose interpolation)
- VITE_GOOGLE_CLIENT_ID
- INSTALL_SPACY_MODEL
- LAB_OPENDATALOADER_HYBRID_URL
- See `.env.example` at the repo root.

## 10. API Surface (High-Level)

All website routes live under `/api/v1/*` (frozen contract). The mobile app
uses `/api/v2/*` for structured lab results, and the `/api/v1` patient routes
for auth, documents, profile, doctors and sharing.

### Auth (`/api/v1`)
- POST /api/v1/auth/token
- POST /api/v1/auth/google-login
- POST /api/v1/auth/register

### Patient (`/api/v1`)
- POST /api/v1/patient/upload/
- GET /api/v1/patient/documents
- DELETE /api/v1/patient/documents/{document_id}
- GET /api/v1/patient/linked-doctors

### Doctor (`/api/v1`)
- GET /api/v1/doctor/patients
- GET /api/v1/doctor/patients/{patient_id}/documents

### Linking (`/api/v1`)
- POST /api/v1/patient/generate-access-code
- POST /api/v1/doctor/link-patient

### Documents (`/api/v1`)
- GET /api/v1/documents/{document_id}
- POST /api/v1/documents/{document_id}/analyze
- POST /api/v1/documents/{document_id}/verify
- POST /api/v1/documents/{document_id}/notes
- POST /api/v1/documents/{document_id}/archive
- GET /api/v1/documents/{document_id}/download

### Profile (`/api/v1`)
- GET /api/v1/profile
- PUT /api/v1/profile

### Sharing (`/api/v1`)
- POST /api/v1/patient/documents/{document_id}/share/{doctor_id}
- DELETE /api/v1/patient/documents/{document_id}/share/{doctor_id}
- GET /api/v1/patient/documents/{document_id}/shared-doctors

### Lab reports (`/api/v2`)
- POST /api/v2/lab-reports/upload (file + full Stages 1-3 pipeline)
- POST /api/v2/lab-reports/upload-structured (app structured ingest, `source: "app"`)
- GET /api/v2/lab-reports (patient's own)
- GET /api/v2/lab-reports/patient/{patient_id} (doctor view)
- GET /api/v2/lab-reports/{id} (full annotated structure)

## 11. Testing

### Backend

```bash
cd backend
python -m pytest tests/ -v
```

- `tests/test_rule_engine.py` — Stage 3 flagging + pattern detection (pure, no DB)
- `tests/test_v2_structured_ingest.py` — app ingest payload validation (no DB)

### Backend smoke test script

```bash
python test_ai_services.py
```

Note:
- This script performs basic direct service checks and is not a full integration test suite.

### Manual integration path
1. Register patient and doctor users
2. Generate patient access code and link doctor
3. Upload a sample document
4. Trigger AI analysis
5. Verify doctor can review, add notes, and verify

### Mobile

```bash
cd mobile
flutter test
flutter analyze
```

- `test/t5_tokenizer_test.dart` — Dart SentencePiece port vs HF reference vectors
- `test/widget_test.dart` — normalization schema correctness (never flag fields)
- `test/sync_queue_test.dart` — queue serialization, preprocess layout, `source: "app"`

## 12. Deployment

Production deployment guide is in:
- DEPLOYMENT.md

Current target architecture:
- Frontend on Vercel
- Backend on Modal
- Database and storage on Supabase

## 13. Security and Compliance Notes

- Never commit real secrets in .env files
- Restrict CORS to trusted origins in production
- Use strong SECRET_KEY and rotate credentials periodically
- Keep medical documents private and enforce role checks in every endpoint path

## 14. Project Report Writing Guide

Use this README as your base and structure your report with these sections:

1. Introduction and problem statement
2. Objectives and scope
3. System architecture (frontend, backend, DB, storage, AI, mobile)
4. Feature modules (auth, linking, documents, AI analysis, lab pipeline, app sync)
5. Database design (Prisma schema entities and relations)
6. API design and endpoint mapping
7. AI pipeline details and limitations
8. Security considerations
9. Deployment strategy
10. Testing strategy and results
11. Challenges faced and improvements planned
12. Conclusion

Suggested quantitative items to include in your report:
- Number of API endpoints (v1 frozen + v2 lab/ingest)
- Number of core DB entities (incl. LabReport)
- AI service components (OCR/NLP/CV + T5 summarizer)
- On-device parity evidence (ONNX checker, HF greedy-prefix match, tokenizer vectors)
- Measured response times for analyze endpoint (local and deployed)
- Error/fallback cases tested

## 15. Cleanup Policy for This Repo

Keep in version control:
- Source code
- Config templates (.env.example)
- Deployment and architecture docs

Do not commit:
- Virtual environments (venv/, .venv/)
- Cache and bytecode (__pycache__/, .pytest_cache/, .mypy_cache/)
- Local uploads/temp artifacts
- Secret env files (.env)
- Large generated binaries unless intentionally versioned (tracked exceptions:
  mobile ONNX/tokenizer artifacts + backend T5 export configs, via LFS)
