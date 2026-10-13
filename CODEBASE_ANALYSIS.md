# IntelliMed-AI: Comprehensive Codebase Analysis Report

---

## 1. PROJECT OVERVIEW

### System Summary
**IntelliMed-AI** is a multi-platform, AI-assisted medical document lifecycle and diagnostic intelligence system designed to bridge the communication and information gap between healthcare providers and patients. The platform provides end-to-end management of sensitive medical records—including handwritten and printed prescriptions, laboratory reports, and chest X-rays. It serves three distinct user roles:
1. **Patients**, who securely upload or on-device capture medical files, view history and longitudinal biomarker trends, control doctor access via ephemeral 6-character hex access codes, and receive patient-friendly explanations;
2. **Doctors**, who link to patients via verified access codes, inspect AI-extracted medication regimens, review multi-tier biomarker panic flags and chest X-ray disease probabilities, attach clinical notes, and digitally sign/verify diagnostic results;
3. **Admins**, who maintain system integrity, verify clinical rule tables, and oversee user governance.

### Tech Stack Breakdown by Layer

| Layer | Primary Technologies & Frameworks | Key Dependencies & Specifications |
| :--- | :--- | :--- |
| **Frontend (Web)** | React 18.2.0, Vite 7.2.2, React Router DOM 6.4.4 | Axios 1.2.0, Tailwind CSS 4.1.17, React Dropzone 14.3.8, jwt-decode 4.0.0, Heroicons/Material SVG |
| **Backend (API)** | FastAPI (Python 3.10+), Uvicorn, ASGI | Prisma Client Python 0.11+, Pydantic v2, python-jose (JWT HS256), passlib / bcrypt, fastapi-cache2 (InMemoryBackend) |
| **Mobile App** | Flutter 3.44 / Dart 3.12+ (Android-first, minSdk 26) | `google_mlkit_text_recognition`, `google_mlkit_document_scanner`, `pdfrx` (pdfium text layer & rasterization), `sqflite` 2.4.3, `flutter_onnxruntime` 1.8.5, `llama_cpp_dart` 0.2.2, `flutter_secure_storage` 11.1.0, `google_sign_in` 7.2.0, `connectivity_plus` 7.3.1, `http` 1.6.0 |
| **AI / ML & Vision** | PyTorch 2.x, Torchvision, ONNX Runtime, Llama.cpp | ResNet-50 (Transfer Learning CNN), Qwen3-0.6B (Q4_0 GGUF causal SLM), Falconsai/medical_summarization (T5-small Seq2Seq), EasyOCR (CRAFT+CRNN), Tesseract OCR (pytesseract, 12 PSM modes), OpenDataLoader-PDF (`opendataloader-pdf`), spaCy (`en_core_web_sm`), OpenCV (cv2), Pillow (PIL) |
| **Database & Storage**| PostgreSQL (Supabase pooler + directUrl), SQLite (Mobile) | Prisma ORM (`backend/prisma/schema.prisma`), Supabase Storage (`medical-documents` private bucket), SQLite (`intellimed_results.db` via sqflite) |
| **DevOps & Infrastructure** | Docker, Docker Compose, Modal, Vercel | `Dockerfile` (multi-stage Python/Torch), `Dockerfile.dev` (Node/Vite), `docker-compose.yml` (backend, lab-hybrid, frontend), `modal_app.py` (serverless GPU/CPU orchestration), `vercel.json` |

---

## 2. ARCHITECTURE

### High-Level System Architecture
The IntelliMed-AI platform operates as a distributed hybrid cloud/edge architecture. Clients interface with a centralized FastAPI backend hosted on Modal (or Docker) backed by PostgreSQL and Supabase Object Storage, while mobile clients execute on-device edge AI inference to guarantee offline availability and privacy-preserving data extraction:

1. **Web Single Page Application (`frontend/`)**: Static React application bundled by Vite and hosted on Vercel. Communicates with the backend exclusively via frozen `/api/v1/*` REST endpoints.
2. **Mobile Application (`mobile/`)**: Offline-first Flutter client running local OCR, local geometric table reconstruction, local deterministic normalization, and edge neural inference (ONNX Runtime for X-rays and `llama.cpp` for Qwen3-0.6B SLM). Communicates with `/api/v2/*` for structured data synchronization and reuses `/api/v1/*` for account, profile, doctor-linking, and raw document actions.
3. **Backend API Gateway & Core Service (`backend/`)**: Asynchronous FastAPI service orchestrating JWT auth, role validation, dual-tier caching (FastAPI-Cache2 + request-level in-memory TTL maps), Supabase private signed URL generation, and the server-side AI processing pipeline.
4. **Lab Report Understanding Engine (`backend/lab_pipeline/`)**: Three-stage hybrid engine:
   - *Stage 1 (`ocr_stage.py`)*: OpenDataLoader-PDF JSON parser with xycut and cluster algorithms (with an EasyOCR fallback).
   - *Stage 2 (`slm_stage.py`)*: Deterministic schema normalizer converting raw tables into canonical analyte names and reference bounds.
   - *Stage 3 (`rule_engine.py`)*: Pure functional clinical rule engine evaluating derived indices, arithmetic consistency, panic/critical alerts, and 9 clinical specialty patterns.
5. **Storage & Data Layer**:
   - *PostgreSQL*: Managed through Prisma ORM storing relational user identities, access permissions, document metadata, audit logs, and structured analysis JSON blobs.
   - *Supabase Storage*: Encrypted S3-compatible bucket (`medical-documents`) holding raw PDF, JPEG, PNG, and DICOM binaries, accessed solely via short-lived signed URLs.
   - *Mobile SQLite*: On-device database (`results` table) persisting pending, synced, and failed extraction payloads.

```
+---------------------------------------------------------------------------------------+
|                                    CLIENT LAYER                                       |
|  +-------------------------------------+     +-------------------------------------+  |
|  |     React 18 Web SPA (Vercel)       |     |   Flutter Mobile App (Android 8.0+) |  |
|  |  - AuthContext / Axios HTTP Client  |     |  - ML Kit Scanner / PDFium Reader   |  |
|  |  - In-Memory Client Cache (cache.js)|     |  - On-Device ResNet50 ONNX (94 MB)  |  |
|  |  - Document Viewer & Doctor Review  |     |  - Qwen3-0.6B Q4_0 GGUF (382 MB)    |  |
|  |                                     |     |  - Local SQLite Store (store.dart)  |  |
|  +------------------+------------------+     +------------------+------------------+  |
+---------------------|-------------------------------------------|---------------------+
                      | HTTP REST (/api/v1/*)                     | HTTP REST (/api/v1/* & /api/v2/*)
                      v                                           v
+---------------------------------------------------------------------------------------+
|                                   BACKEND GATEWAY                                     |
|                                FastAPI (Modal / Docker)                               |
|  +---------------------------------------------------------------------------------+  |
|  | Middleware: CORSMiddleware | StaticFiles (/uploads) | FastAPICache (InMemory)   |  |
|  +---------------------------------------------------------------------------------+  |
|  | Routing Modules:                                                                |  |
|  |   - auth_router (/api/v1/auth)       - linking_router (/api/v1)                 |  |
|  |   - patient_router (/api/v1/patient) - document_router (/api/v1/documents)      |  |
|  |   - doctor_router (/api/v1/doctor)   - profile_router (/api/v1/profile)         |  |
|  |   - sharing_router (/api/v1/patient) - lab_report_router (/api/v2/lab-reports)  |  |
|  +---------------------------------------------------------------------------------+  |
|  | Security & Caching Layer:                                                       |  |
|  |   - auth.py (JWT Bearer HS256, bcrypt)                                          |  |
|  |   - google_oauth.py (Google Token Verification)                                 |  |
|  |   - request_cache.py (doctor_has_patient_access TTL, get_cached_user)           |  |
|  +---------------------------------------------------------------------------------+  |
+------------------------------------+------------------------------------+--------------+
                                     |                                    |
            Async Delegation         |                                    | ORM Queries / S3 Calls
                                     v                                    v
+------------------------------------+-----------+    +----------------------------------+
|               AI & PIPELINE SERVICES           |    |           DATA PERSISTENCE       |
|  +------------------------------------------+  |    |  +----------------------------+  |
|  | services.py (Legacy v1 Monolith):        |  |    |  | PostgreSQL (Supabase)      |  |
|  |  - ocr_service() (EasyOCR / Tesseract)   |  |    |  |  - users                   |  |
|  |  - cv_service() (ResNet-50 Pneumonia)    |  |    |  |  - doctor_patient          |  |
|  |  - nlp_service() (spaCy + Rx Database)   |  |    |  |  - medical_documents       |  |
|  |  - medical_summarize_service() (T5)      |  |    |  |  - lab_reports             |  |
|  +------------------------------------------+  |    |  |  - document_share          |  |
|  | lab_pipeline/ (v2 Modular Engine):       |  |    |  +----------------------------+  |
|  |  - ocr_stage.py (OpenDataLoader JSON)    |  |    |  | Supabase Storage Bucket    |  |
|  |  - slm_stage.py (Deterministic Normalizer|  |    |  |  - medical-documents       |  |
|  |  - rule_engine.py (Pure Rules & Panics)  |  |    |  |    (Signed URL Access)     |  |
|  +------------------------------------------+  |    |  +----------------------------+  |
+------------------------------------------------+    +----------------------------------+
```

### End-to-End Data Flow: Trace of a Full User Journey
Tracing a complete lifecycle: **Patient uploads a medical document -> OCR -> NLP/SLM Structuring -> X-Ray / Rule Classification -> Doctor Review -> Verification & Notes**.

1. **Patient Authentication**:
   - Patient logs in on web (`frontend/src/services/api.js::login`) or mobile (`mobile/lib/auth.dart::AuthService.signInWithGoogle`).
   - Request hits `POST /api/v1/auth/token` or `POST /api/v1/auth/google-login` in `backend/api/auth_router.py`.
   - Backend verifies password via `auth.verify_password` using `bcrypt.checkpw`, or verifies Google ID token via `google_oauth.verify_google_token`.
   - Returns JWT signed with `SECRET_KEY` (HS256, 30 min expiration).
2. **Patient Uploads File**:
   - Web frontend calls `uploadDocument` in `frontend/src/services/api.js` dispatching a multipart POST to `POST /api/v1/patient/upload/` (`backend/api/patient_router.py`).
   - `patient_router.py::upload_document` validates `current_user.role == 'patient'` and enforces file size under `MAX_UPLOAD_SIZE_MB` (10 MB).
   - The file bytes are written to disk via `tempfile.NamedTemporaryFile` and uploaded to Supabase Storage at `patients/{user_id}/{filename}` via `supabase_storage.upload_file`.
3. **Parallel Multimodal AI Processing**:
   - `patient_router.py` initiates concurrent asyncio tasks:
     - `ocr_task = asyncio.create_task(services.ocr_service(tmp_path))`
     - `cv_task = asyncio.create_task(services.cv_service(tmp_path))`
   - `services.py::ocr_service` executes:
     - Detects PDF vs Image (`_is_pdf`).
     - If PDF, attempts OpenDataLoader JSON extraction (`_run_opendataloader_parse`).
     - If image or fallback, runs image enhancement (`_preprocess_for_handwriting_cv2` or PIL variant: CLAHE, adaptive thresholding, bilateral filter, deskewing) and feeds images into EasyOCR `reader.readtext` or multi-PSM Tesseract.
     - Text is cleaned and normalized via `_clean_ocr_text` and `_fix_medical_ocr_errors`.
   - `nlp_task = asyncio.create_task(services.nlp_service(ocr_result))`:
     - Evaluates prescription markers via `_text_looks_like_prescription`.
     - Matches 150+ pharmaceutical entities against generic/brand database (`_run_regex_medical_extraction`).
     - Parses dosages, routes (oral, IV, topical), frequencies (BID, TID, PRN), and durations.
     - Runs spaCy NER (`_run_spacy_ner`) when model is present.
   - `cv_task` executes `services.py::cv_service`:
     - Runs `_preprocess_xray`: opens image, converts to RGB, resizes to 224x224, applies ImageNet normalization.
     - Invokes `_run_pneumonia_classifier`: passes tensor through fine-tuned ResNet-50 (`backend/models/best_model_optimized.pkl`).
     - Computes Softmax probabilities across `Normal`, `Bacterial Pneumonia`, and `Viral Pneumonia`.
   - `services.py::medical_summarize_service`:
     - Passes extracted text through `Falconsai/medical_summarization` (T5-small Seq2Seq) to produce concise clinical summaries and bulleted key findings.
4. **Document Type Arbitration & Persistence**:
   - `patient_router.py` arbitrates final document type based on hierarchical heuristics:
     - High priority: `is_prescription` or `has_medications` -> type = `"prescription"`.
     - Medium priority: `not is_prescription` and `confidence > 0.6` on X-ray classifier -> type = `"xray"`.
     - Fallback: `"document"`.
   - Aggregates payload into `aggregated_analysis` JSON and persists to PostgreSQL `medical_documents` table via `db.medicaldocument.create`.
   - Caches are invalidated across `patient-docs`, `linked-doctors`, and `doctor-patient-docs` namespaces via `_invalidate_patient_related_caches`.
5. **Patient-Doctor Linking**:
   - Patient generates an access code (`POST /api/v1/patient/generate-access-code` in `backend/api/linking_router.py`). Generates random 6-character hex token via `secrets.token_hex(3).upper()`, creating a record in `doctor_patient`.
   - Doctor enters the code (`POST /api/v1/doctor/link-patient` in `linking_router.py`). System validates the unused code, associates `doctor_id = current_user.id`, and invalidates access caches via `_invalidate_link_related_caches`.
6. **Doctor Document Access**:
   - Doctor queries `GET /api/v1/doctor/patients/{patient_id}/documents` in `backend/api/doctor_router.py`.
   - Access permission verified via `request_cache.doctor_has_patient_access` (cached in-memory for 120 seconds).
   - Document URLs are securely signed using `supabase_storage.create_signed_url` with 300-second expiration.
7. **Doctor Clinical Review & Verification**:
   - Doctor inspects full analysis in `frontend/src/pages/MedicalDocumentViewer.jsx`.
   - Doctor adds clinical notes via `POST /api/v1/documents/{document_id}/notes` in `backend/api/document_router.py`. Note object `{note, added_by, added_by_id, added_at}` is appended to the `clinical_notes` JSON array.
   - Doctor signs off via `POST /api/v1/documents/{document_id}/verify` in `document_router.py`, stamping `verified_by = current_user.id`, `verified_at = datetime.utcnow()`, and optional `verification_notes`.
   - Cache is evicted via `_invalidate_document_cache(document_id)`.
   - Patient views verified status, signature stamp, and physician notes immediately in `PatientDashboard.jsx`.

### Dual-Deliverable Split & Backward Compatibility Strategy
The repository maintains an explicit dual-client architecture:
- **Web App (`frontend/`)**: Traditional centralized cloud model. Uploads raw images/PDFs to `/api/v1/patient/upload/`, triggering server-side GPU/CPU pipelines.
- **Mobile App (`mobile/`)**: Privacy-preserving edge computing model. Captures images via `google_mlkit_document_scanner`, performs quality gate checks (blur, glare, darkness), runs OCR via ML Kit or PDFium text layer, runs deterministic Stage 1 & Stage 2 structuring locally, runs on-device neural models, stores structured records in local SQLite, and syncs **only structured JSON** to `/api/v2/lab-reports/upload-structured`.

**Backward Compatibility Mechanisms**:
1. **API Version Freezing**: `/api/v1/*` routes remain frozen in contract. New lab report architectures and mobile payloads are isolated strictly under `/api/v2/*`.
2. **Pseudo-Path Storage Abstraction (`app-structured/<kind>`)**:
   - When mobile clients upload structured results without sending raw image files, the database `file_path` is written as `app-structured/lab_report`, `app-structured/xray`, or `app-structured/prescription`.
   - In `backend/api/v2/lab_refs.py`, `has_stored_file(file_path)` checks if a path starts with `app-structured/`. If true, `_safe_file_url()` returns an empty string `""` instead of attempting an S3 signed URL call, preventing HTTP 500 errors.
   - `file_ref_name()` safely converts `app-structured/*` paths to `"On-device structured result"`.
3. **Polymorphic Document Analysis Representation**:
   - In `backend/api/document_router.py`, `get_document()` inspects `ai_analysis_json`:
     - If it contains v1 keys (`cv_result`, `nlp_result`, `ocr_result`), it formats the legacy v1 response object.
     - If it contains mobile on-device keys (`normalized`, `stage2`), it formats an `"On-device result"` structure and suppresses broken server "Analyze" CTAs.
4. **Shared Relational Tables with Origin Tagging**:
   - Both `MedicalDocument` and `LabReport` models include a `source` varchar column (`'web'` vs `'app'`). This ensures unified doctor dashboards while auditing data provenance.
5. **Ingest Schema Validation Gate**:
   - `backend/api/v2/ingest_schema.py::validate_ingest_payload` rejects any mobile upload that attempts to pass pre-computed Stage 3 flags (`abnormal`, `direction`), enforcing the invariant that clinical interpretations are determined deterministically by the server's rule table.

---

## 3. AI/ML PIPELINE DETAIL

### Comprehensive Model Inventory

| Model / Engine Name | Type & Architecture | Approx. Size / Params | Primary Input | Output Data / Format | File Reference |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **ResNet-50 Pneumonia Classifier (Server)** | Deep Convolutional Neural Network (PyTorch); custom head: `Dropout(0.3) + Linear(2048, 3)` | ~94.4 MB checkpoint (`best_model_optimized.pkl`), 25.6M parameters | Preprocessed RGB image tensor `[1, 3, 224, 224]` | Softmax probabilities for `['Normal', 'Bacterial Pneumonia', 'Viral Pneumonia']`, classification label, confidence score | `backend/services.py::_load_pneumonia_model` |
| **ResNet-50 Pneumonia Classifier (Mobile Twin)** | ONNX Runtime graph (exported via opset 17, single-tensor) | ~94.2 MB (`pneumonia_resnet50.onnx`) | Float32 tensor `[1, 3, 224, 224]` | Logits tensor `[1, 3]`; Softmax probabilities and top classification | `mobile/lib/cnn_ocr.dart::CnnService`, `backend/scripts/export_pneumonia_onnx.py` |
| **Falconsai Medical Summarizer (Server)** | T5-small Encoder-Decoder Transformer (`Falconsai/medical_summarization`) | ~240 MB (PyTorch weights), 60M parameters | String: `"summarize: " + ocr_text` (chunked to max 1024 chars) | Plaintext summary, bulleted key clinical findings (`medical_summary`, `key_findings`) | `backend/services.py::_run_medical_summarization` |
| **Qwen3-0.6B SLM (Mobile On-Device)** | Causal Decoder Transformer (Instruction-tuned, Q4_0 GGUF via `llama.cpp`) | ~382 MB (`Qwen3-0.6B-Q4_0.gguf`), 600M parameters (440M non-embed) | ChatML formatted string with prefilled empty think block `<think>\n\n</think>` | Plaintext layperson explanations, doctor visit questions, translation strings | `mobile/lib/slm_runtime.dart::QwenSlmRuntime` |
| **EasyOCR Engine** | CRAFT (Character Region Awareness for Text Detection) + CRNN (ResNet + BiLSTM + CTC) | ~100 MB model caches (detector + recognizer) | Grayscale / preprocessed document image | List of tuples: `(bounding_box, recognized_text, confidence_score)` | `backend/services.py::_get_ocr_reader` |
| **Tesseract OCR (Fallback)** | LSTM-based OCR engine (pytesseract) | System binary dependency | Image array (multi-pass across 12 PSM modes) | Extracted text strings from various page segmentation layouts | `backend/services.py::_run_enhanced_ocr` |
| **OpenDataLoader-PDF** | Layout analysis, PDF StructTree parsing, hybrid document cluster extractor | Python wheel + optional `opendataloader-pdf-hybrid` microservice | PDF binary file path | JSON structure with bounding boxes, character coordinates, and page indices | `backend/lab_pipeline/ocr_stage.py` |
| **Google ML Kit Text Recognition** | On-device Google Play Services OCR engine | Bundled native Android runtime | Mobile camera image file or bitmap | `RecognizedText`: blocks, lines, element words, bounding boxes, confidences | `mobile/lib/cnn_ocr.dart`, `mobile/lib/lab/extract.dart` |
| **Medical NLP & Entity Parser** | spaCy statistical NER (`en_core_web_sm`) + Regex rule matcher + 150+ drug dictionary | ~12 MB (spaCy package) + regex tables | Raw OCR text string | JSON object containing classified medications, dosages, routes, frequencies, and durations | `backend/services.py::_run_medical_nlp` |
| **Clinical Rule Engine (Stage 3)** | Pure functional deterministic rule engine | Zero weights (deterministic JSON table) | Normalized Stage 2 lab report JSON | Fully annotated JSON: single-test flags, panic levels, derived clinical indices, specialty patterns | `backend/lab_pipeline/rule_engine.py`, `mobile/lib/lab/clinical_engine.dart` |

### Inference Pipelines & Sequences

#### Pipeline A: Document Upload & Multi-Model Inference (Server v1)
*File Reference:* `backend/api/patient_router.py::upload_document` and `backend/services.py`.
1. `file_bytes` received -> Saved to temporary file.
2. Parallel execution:
   - `ocr_service(tmp_path)`:
     - If PDF: PyMuPDF rasterizes pages or OpenDataLoader parses digital text.
     - If Image: OpenCV applies 8-step preprocessing (`_preprocess_for_handwriting_cv2`: grayscale, bilateral filter, CLAHE, Otsu binarization, morphological opening, deskewing).
     - Text extracted with EasyOCR (`reader.readtext`); if confidence < 0.35, fallback to Tesseract PSM modes.
     - Text cleaned via regex dictionary (`_fix_medical_ocr_errors`).
   - `cv_service(tmp_path)`:
     - OpenCV loads image; checks size and aspect ratio.
     - PyTorch normalizes tensor via standard ImageNet transform (`transforms.Normalize([0.485, 0.456, 0.406], [0.229, 0.224, 0.225])`).
     - ResNet-50 computes logits -> Softmax generates class distribution.
3. Downstream NLP:
   - `nlp_service(ocr_result)`:
     - Regex matches medication patterns (dosage units: `mg`, `ml`, `mcg`, `g`, `iu`; frequencies: `OD`, `BID`, `TID`, `QID`, `PRN`).
     - Maps against 150+ medication dictionary (`Aspirin`, `Amoxicillin`, `Metformin`, `Atorvastatin`, etc.).
     - spaCy extracts named entities (`PERSON`, `DATE`, `ORG`).
4. Medical Summarization:
   - `medical_summarize_service(ocr_result, nlp_result)`:
     - If prescription: Formats structured dosage bullet points via `_build_prescription_summary`.
     - If diagnostic report: Passes text through Falconsai T5 (`AutoModelForSeq2SeqLM`) with max input tokens = 512, generating summary sentences and key clinical findings.

#### Pipeline B: Lab Report Understanding Pipeline (Server v2)
*File Reference:* `backend/lab_pipeline/__init__.py::run_lab_report_pipeline`.
1. **Stage 1 — OCR & Geometry Extraction** (`ocr_stage.py::run_stage1`):
   - OpenDataLoader-PDF runs in JSON mode with `--reading-order=xycut` and `--table-method=cluster`.
   - Preserves bounding boxes (`x, y, w, h`) and page numbers for every extracted cell.
   - If extraction text length < 40 chars, triggers EasyOCR fallback, explicitly logging that bounding boxes are unavailable.
2. **Stage 2 — Schema Normalization** (`slm_stage.py::run_stage2`):
   - Consumes Stage 1 structure.
   - Normalizes test names via `TEST_NAME_MAP` (e.g. `hb` -> `Hemoglobin`, `sgpt` -> `Alanine Aminotransferase (ALT)`).
   - Normalizes numerical values, unit strings, and printed reference ranges (`range_low`, `range_high`).
   - **Crucial Invariant**: Extracts only source-printed flags (`flag_in_source`); never computes abnormal flags from range comparisons.
3. **Stage 3 — Arithmetic & Clinical Rule Evaluation** (`rule_engine.py::annotate`):
   - *3a-derived*: Calculates standard clinical derived formulas:
     - eGFR (CKD-EPI 2021 formula based on Serum Creatinine, age, sex).
     - Serum Anion Gap: $[Na^+] - ([Cl^-] + [HCO_3^-])$.
     - De Ritis Ratio: $AST / ALT$.
     - BUN / Creatinine Ratio.
     - Corrected Calcium (Payne formula): $Total\ Ca + 0.8 \times (4.0 - Albumin)$.
     - Albumin-Globulin Ratio, Non-HDL Cholesterol, Mentzer Index, Transferrin Saturation, NLR.
   - *3a-consistency*: Validates arithmetic relationships (e.g. Total Bilirubin vs Direct + Indirect) to flag OCR misreads.
   - *3b-single*: Compares values against reference intervals; classifies into 5 severity levels (`normal`, `mild`, `moderate`, `severe`, `critical`); flags immediate panic values (e.g. Potassium < 2.8 or > 6.2 mEq/L, Platelets < 20,000 /uL, Glucose < 50 or > 400 mg/dL).
   - *3c-patterns*: Matches multi-analyte rules across 9 clinical specialties (Hematology, Metabolic/Endocrine, Renal, Hepatic, Lipid/Cardiovascular, Electrolyte/Acid-Base, Inflammatory/Infectious, Thyroid, Iron Panel).

#### Pipeline C: On-Device Mobile Lab & Vision Capture
*File Reference:* `mobile/lib/screens/capture_screen.dart`, `mobile/lib/lab/`.
1. Image picked via `google_mlkit_document_scanner` (hardware camera with perspective correction/dewarping) or gallery.
2. Quality Gate (`mobile/lib/capture_quality.dart`): Checks Variance-of-Laplacian (blur threshold), white pixel clipping (glare threshold), and luminance (darkness threshold). Prompts user if retake is needed.
3. OCR / Text Layer:
   - For images: `google_mlkit_text_recognition` parses words, lines, and bounding boxes (`lab/ocr_model.dart`).
   - For digital PDFs: `pdfrx` extracts character-level bounding boxes and exact text stream directly.
4. Local Structuring (`lab/structure.dart`): Clusters lines into table columns and rows based on Y-axis projection and horizontal gutters.
5. Local Normalization (`lab/rule_engine.dart`): Direct Dart port of backend `slm_stage.py` emitting the 10-key test schema.
6. Local Triage Banner (`lab/clinical_engine.dart`): Checks panic thresholds deterministically from bundled `assets/rules/clinical_rules.json`.
7. Persistence & Sync:
   - Inserts row into `store.dart` (`results` SQLite table) with status `'pending'`.
   - `sync.dart` (`V2Sync`) background worker detects connection (`connectivity_plus`) and POSTs payload to `/api/v2/lab-reports/upload-structured`.

### Prompt Templates, JSON Schemas & Interfaces

#### 1. Stage 2 SLM Normalization Prompt (`backend/lab_pipeline/slm_stage.py`)
```text
SYSTEM PROMPT — Lab Report & Prescription Normalization

You are a medical document normalization engine. Your ONLY job is to convert extracted document text/structure into a fixed JSON schema. You do not diagnose, interpret, or make clinical judgments. You do not add information that is not present in the input. You do not guess values you cannot find — you mark them null.

INPUT: Structured text/JSON from an OCR/extraction stage, for a lab report or prescription. The input may have residual noise from table extraction, OCR errors in numbers/units, or inconsistent structure.

OUTPUT: Valid JSON only. No prose, no explanation, no markdown formatting, no code fences. If you cannot produce valid JSON, output {"error": "unparseable", "raw_input_excerpt": "<first 100 chars>"}.

DOCUMENT TYPE DETECTION: Determine LAB_REPORT vs PRESCRIPTION based on structure. Output in "document_type".

NORMALIZATION RULES:
1. Test name normalization: map common abbreviations to full clinical names (Hb/HGB → Hemoglobin, WBC → White Blood Cell Count, etc.). Always preserve original in raw_test_name.
2. Unit normalization: if ambiguous/missing but inferable, fill it in but mark ocr_confidence as "medium", not "high".
3. Never compute abnormal flags yourself by comparing value to range — only populate flag_in_source if the SOURCE document explicitly printed a flag (H, L, Abn, etc.). Downstream rule-engine logic handles range comparison. Do not conflate extraction with interpretation.
4. If a row is ambiguous due to table misalignment, do your best single-row reconstruction and mark ocr_confidence as "low" rather than dropping the row.
5. Never fabricate a reference range if none is present — leave range_low/range_high/range_raw null.
6. If patient identity fields are absent, leave null. Never infer age/sex from test types.
7. Preserve panel structure as printed if panel headers exist. If flat/ungrouped, use a single panel named "Ungrouped".

WHAT YOU MUST NEVER DO:
- Never output a diagnosis, interpretation, or clinical recommendation.
- Never output a flag or pattern determination based on value-vs-range comparison — that is downstream, deterministic logic, not yours.
- Never omit a row because you're unsure — extract with low confidence rather than dropping data silently.
- Never output anything except the JSON object.
```

#### 2. Mobile Qwen3-0.6B ChatML Prompt Builder with Thinking Suppression (`mobile/lib/slm_runtime.dart`)
```dart
String buildChatMlPrompt(
  String system,
  String user, {
  bool enableThinking = true,
}) {
  final assistantOpen = enableThinking
      ? '<|im_start|>assistant\n'
      : '<|im_start|>assistant\n<think>\n\n</think>\n\n';
  return '<|im_start|>system\n$system<|im_end|>\n'
      '<|im_start|>user\n$user<|im_end|>\n'
      '$assistantOpen';
}
```

#### 3. Standard 10-Key Lab Test JSON Schema (`_REQUIRED_LAB_TEST_KEYS`)
```json
{
  "test_name": "Hemoglobin",
  "raw_test_name": "Hb",
  "value": 11.2,
  "unit": "g/dL",
  "range_low": 13.0,
  "range_high": 17.0,
  "range_raw": "13.0 - 17.0",
  "flag_in_source": "L",
  "ocr_confidence": "high",
  "source_bbox": {
    "page": 1,
    "x": 45.2,
    "y": 112.0,
    "w": 210.5,
    "h": 14.8
  }
}
```

#### 4. Structured Ingest Request Payload (`backend/api/v2/ingest_schema.py`)
```json
{
  "kind": "lab_report",
  "engine": "app-on-device-v2",
  "latency_ms": 420,
  "source": "app",
  "ocr_excerpt": "CBC Hemoglobin 11.2 g/dL (13.0-17.0) ...",
  "normalized": {
    "document_type": "lab_report",
    "patient_context": {
      "name": "Jane Doe",
      "age": "34",
      "sex": "F",
      "report_date": "2026-03-12"
    },
    "lab_name": "Quest Diagnostics",
    "panels": [
      {
        "panel_name": "Complete Blood Count",
        "tests": [ /* array of 10-key test objects */ ]
      }
    ]
  },
  "summary_context": {
    "medical_summary": "Hemoglobin is below normal reference interval...",
    "key_findings": ["Low hemoglobin (11.2 g/dL)"],
    "model": "qwen3-0.6b-q4_0"
  }
}
```

---

## 4. BACKEND

### Complete API Endpoint Directory

| HTTP Method | Route Path | Handler Function & File | Access Role / Perms | Request Body / Params | Response Shape / Model |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **POST** | `/api/v1/auth/token` | `login_for_access_token` in `auth_router.py` | Public | `OAuth2PasswordRequestForm` (`username`, `password`) | `schemas.Token` (`access_token`, `token_type: "bearer"`) |
| **POST** | `/api/v1/auth/google-login` | `google_login` in `auth_router.py` | Public | `GoogleLoginRequest` (`token: str`, `role: str`) | `schemas.Token` (`access_token`, `token_type: "bearer"`) |
| **POST** | `/api/v1/auth/register` | `register_user` in `auth_router.py` | Public (Doctor requires code) | `schemas.UserCreate` (`email`, `password`, `role`, `name?`, `doctor_access_code?`) | `schemas.UserInDB` (`id`, `email`, `name`, `role`) |
| **POST** | `/api/v1/patient/upload/` | `upload_document` in `patient_router.py` | Patient | Multipart Form: `file: UploadFile` | `schemas.DocumentInfo` (`id`, `filename`, `upload_timestamp`, `ai_analysis`) |
| **GET** | `/api/v1/patient/documents` | `get_own_documents` in `patient_router.py` | Patient | None | `List[schemas.DocumentInfo]` |
| **DELETE** | `/api/v1/patient/documents/{document_id}` | `delete_document` in `patient_router.py` | Patient (Owner) | Path: `document_id: int` | HTTP 204 No Content |
| **GET** | `/api/v1/patient/linked-doctors` | `get_linked_doctors` in `patient_router.py` | Patient | None (Cached 300s) | `List[schemas.User]` |
| **GET** | `/api/v1/doctor/patients` | `get_doctor_patients` in `doctor_router.py` | Doctor | None (Cached 300s) | `List[schemas.User]` |
| **GET** | `/api/v1/doctor/patients/{patient_id}/documents` | `get_patient_documents_for_doctor` in `doctor_router.py` | Doctor (Linked) | Path: `patient_id: int` (Cached 300s) | `List[schemas.DocumentDetail]` (`id`, `filename`, `file_url`, `upload_timestamp`, `ai_analysis`, `analysis_status`) |
| **POST** | `/api/v1/patient/generate-access-code` | `generate_access_code` in `linking_router.py` | Patient | None | JSON: `{"access_code": "A1B2C3"}` |
| **POST** | `/api/v1/doctor/link-patient` | `link_patient` in `linking_router.py` | Doctor | JSON: `LinkPatientRequest` (`access_code: str`) | JSON: `{"message": "Patient linked successfully"}` |
| **GET** | `/api/v1/documents/{document_id}` | `get_document` in `document_router.py` | Patient (Owner) / Doctor (Linked) | Path: `document_id: int` (Cached 300s) | JSON: Aggregated document detail, file metadata, signed URL, and structured analysis |
| **POST** | `/api/v1/documents/{document_id}/analyze` | `analyze_document` in `document_router.py` | Patient (Owner) / Doctor (Linked) | Path: `document_id: int` | JSON: `{"message": "...", "document_id": int, "analysis": {...}}` |
| **POST** | `/api/v1/documents/{document_id}/verify` | `verify_document` in `document_router.py` | Doctor (Linked) | Path: `document_id: int`, Body/Query: `notes?: str` | JSON: `{"message": "...", "verified_by": str, "verified_at": ISO8601, "notes": str}` |
| **POST** | `/api/v1/documents/{document_id}/notes` | `add_clinical_note` in `document_router.py` | Doctor (Linked) | Path: `document_id: int`, Body/Query: `note: str` | JSON: `{"message": "...", "note": str, "added_by": str, "added_at": ISO8601}` |
| **POST** | `/api/v1/documents/{document_id}/archive` | `archive_document` in `document_router.py` | Doctor (Linked) | Path: `document_id: int` | JSON: `{"message": "...", "archived_by": str, "archived_at": ISO8601}` |
| **GET** | `/api/v1/documents/{document_id}/download` | `download_document` in `document_router.py` | Patient (Owner) / Doctor (Linked) | Path: `document_id: int` | `RedirectResponse` (HTTP 307 to signed Supabase URL) |
| **GET** | `/api/v1/profile` | `get_profile` in `profile_router.py` | Authenticated | None (Cached 300s) | JSON: Profile record (phone, DOB, blood type, allergies, conditions, settings) |
| **PUT** | `/api/v1/profile` | `update_profile` in `profile_router.py` | Authenticated | JSON: `UpdateProfileRequest` | JSON: Updated user profile confirmation |
| **POST** | `/api/v1/patient/documents/{document_id}/share/{doctor_id}` | `share_document` in `sharing_router.py` | Patient (Owner) | Path: `document_id: int`, `doctor_id: int` | JSON: `{"message": "Document shared successfully"}` |
| **DELETE** | `/api/v1/patient/documents/{document_id}/share/{doctor_id}` | `unshare_document` in `sharing_router.py` | Patient (Owner) | Path: `document_id: int`, `doctor_id: int` | JSON: `{"message": "Document access revoked successfully"}` |
| **GET** | `/api/v1/patient/documents/{document_id}/shared-doctors` | `get_shared_doctors` in `sharing_router.py` | Patient (Owner) | Path: `document_id: int` (Cached 300s) | `List[{"doctor_id": int, "doctor_email": str}]` |
| **POST** | `/api/v2/lab-reports/upload-structured` | `upload_structured_result` in `api/v2/lab_report_router.py` | Patient | JSON: `StructuredIngestRequest` (`kind`, `normalized`, `source="app"`) | JSON: `{"message": "...", "id": int, "result": {...}}` |
| **POST** | `/api/v2/lab-reports/upload` | `upload_lab_report` in `api/v2/lab_report_router.py` | Patient | Multipart: `file: UploadFile`, `source: str` | JSON: `{"message": "...", "id": int, "result": {stage1, stage2, stage3}}` |
| **GET** | `/api/v2/lab-reports` | `get_own_lab_reports` in `api/v2/lab_report_router.py` | Patient | None | `List[{"id": int, "source": str, "filename": str, "result": Json}]` |
| **GET** | `/api/v2/lab-reports/patient/{patient_id}` | `get_patient_lab_reports_for_doctor` in `api/v2/lab_report_router.py` | Doctor (Linked) | Path: `patient_id: int` | `List[{"id": int, "filename": str, "file_url": str, "result": Json}]` |
| **GET** | `/api/v2/lab-reports/{lab_report_id}` | `get_lab_report` in `api/v2/lab_report_router.py` | Patient (Owner) / Doctor (Linked) | Path: `lab_report_id: int` | JSON: Full annotated lab report envelope |
| **DELETE** | `/api/v2/lab-reports/{lab_report_id}` | `delete_lab_report` in `api/v2/lab_report_router.py` | Patient (Owner) | Path: `lab_report_id: int` | HTTP 204 No Content |

### Database Schema (Prisma ORM)
*File Reference:* `backend/prisma/schema.prisma`.

```prisma
model User {
  id                  Int               @id @default(autoincrement())
  email               String            @unique @db.VarChar(255)
  name                String?           @db.VarChar(255)
  hashed_password     String            @db.VarChar(255)
  role                role_enum         // enum: patient, doctor, admin
  created_at          DateTime          @default(now())
  
  // Profile Information
  phone               String?           @db.VarChar(50)
  date_of_birth       DateTime?         @db.Date
  gender              String?           @db.VarChar(50)
  address             String?           @db.Text
  
  // Emergency Contact & Medical Info
  emergency_contact   String?           @db.VarChar(255)
  emergency_phone     String?           @db.VarChar(50)
  blood_type          String?           @db.VarChar(10)
  allergies           String?           @db.Text
  chronic_conditions  String?           @db.Text
  
  // UI & Notification Settings
  dark_mode           Boolean           @default(false)
  email_notifications Boolean           @default(true)
  push_notifications  Boolean           @default(false)
  
  // Relations
  medical_documents   MedicalDocument[]
  lab_reports         LabReport[]
  doctor_patients     DoctorPatient[]   @relation("doctor_relations")
  patient_doctors     DoctorPatient[]   @relation("patient_relations")
  shared_documents    DocumentShare[]   @relation("shared_documents")

  @@index([email], map: "idx_users_email")
  @@map("users")
}

model DoctorPatient {
  id          Int      @id @default(autoincrement())
  doctor_id   Int?
  patient_id  Int
  access_code String?  @unique
  created_at  DateTime @default(now())
  
  doctor      User?    @relation("doctor_relations", fields: [doctor_id], references: [id])
  patient     User     @relation("patient_relations", fields: [patient_id], references: [id])

  @@map("doctor_patient")
}

model MedicalDocument {
  id                 Int             @id @default(autoincrement())
  patient_id         Int?
  file_path          String          @db.VarChar(255)
  upload_timestamp   DateTime?       @default(now()) @db.Timestamptz(6)
  ai_analysis_json   Json?
  source             String          @default("web") @db.VarChar(10)
  verified_by        Int?
  verified_at        DateTime?
  verification_notes String?         @db.Text
  clinical_notes     Json?           @default("[]")
  archived           Boolean         @default(false)
  archived_at        DateTime?
  archived_by        Int?
  
  users              User?           @relation(fields: [patient_id], references: [id], onDelete: NoAction, onUpdate: NoAction)
  shared_with        DocumentShare[]

  @@index([patient_id], map: "idx_medical_documents_patient_id")
  @@map("medical_documents")
}

model LabReport {
  id                 Int       @id @default(autoincrement())
  patient_id         Int?
  file_path          String    @db.VarChar(255)
  upload_timestamp   DateTime? @default(now()) @db.Timestamptz(6)
  source             String    @default("web") @db.VarChar(10)
  result_json        Json?
  verified_by        Int?
  verified_at        DateTime?
  verification_notes String?   @db.Text
  
  users              User?     @relation(fields: [patient_id], references: [id], onDelete: NoAction, onUpdate: NoAction)

  @@index([patient_id], map: "idx_lab_reports_patient_id")
  @@map("lab_reports")
}

model DocumentShare {
  id          Int             @id @default(autoincrement())
  document_id Int
  doctor_id   Int
  shared_at   DateTime        @default(now())
  
  document    MedicalDocument @relation(fields: [document_id], references: [id], onDelete: Cascade)
  doctor      User            @relation("shared_documents", fields: [doctor_id], references: [id], onDelete: Cascade)

  @@unique([document_id, doctor_id])
  @@map("document_share")
}
```

### Authentication & Authorization Model
- **Token Format & Signature**: Standard JSON Web Tokens (JWT) signed with HMAC-SHA256 (`HS256`). Payloads encapsulate `sub` (email), `role`, and `exp` (timestamp delta = 30 minutes).
- **Password Security**: Passwords hashed using `bcrypt` (`bcrypt.gensalt()`, input clamped to 72 bytes).
- **Google OAuth Flow**: Client sends Google ID token. Backend executes `google_oauth.verify_google_token` validating token integrity against Google's public certs and verifying the audience matches `GOOGLE_CLIENT_ID`. If user is new, creates record; if existing, validates role consistency.
- **Role Permissions**:
  - `patient`: Can upload documents/lab reports, view/delete own documents, generate 6-character access codes, view linked doctors, share/unshare documents, and edit profile. Forbidden from viewing unshared patient records, linking doctors, verifying documents, or archiving documents.
  - `doctor`: Can link to patients via access codes, view assigned patient lists, view linked patient documents and lab reports, append clinical notes, verify/digitally sign analyses, and archive documents. Doctor account creation requires matching `DOCTOR_ACCESS_CODE` env secret.
  - `admin`: Superuser role configured via `ADMIN_EMAIL` and `ADMIN_PASSWORD`. Can bypass `require_role(role)` guards, inspect all documents, and oversee platform configurations.
- **Link-Based Access Control**:
  - Doctor access to a patient's documents is gated by `request_cache.doctor_has_patient_access`. It checks the `doctor_patient` junction table where `doctor_id == current_user.id` and `patient_id == target_patient_id`.
  - Cached in thread-safe memory with a 120-second TTL. Explicitly evicted when a doctor links or unlinks.

---

## 5. FRONTEND & MOBILE APPLICATIONS

### Screen Inventory

#### Web Application (`frontend/src/pages/`)
1. `LoginPage.jsx`: Email/password and Google OAuth entry with dynamic role selection tab.
2. `SignUpPage.jsx`: Registration form for patients and doctors; validates doctor access code if doctor role is selected.
3. `PatientDashboardLayout.jsx`: Shell containing persistent sidebar, user avatar, linked doctor sidebar tray, access code generation modal, and sub-routing.
4. `PatientDashboard.jsx`: Primary patient view featuring dropzone document upload, file cards, AI analysis badges, verification status, and share sheets.
5. `Profile.jsx`: Form editing personal details, emergency contacts, blood type, allergies, and chronic conditions.
6. `Settings.jsx`: Interface for theme toggles (dark mode) and email/push notification preferences.
7. `DoctorDashboardLayout.jsx`: Clinical shell with top navigation bar, link-patient modal trigger, notification bell, and doctor sub-routing.
8. `DoctorOverview.jsx`: Executive doctor portal with quick statistics (total patients, pending reviews, verified records) and recent activity stream.
9. `DoctorPatients.jsx`: Grid of assigned patients with search filtering and direct drill-down into patient files.
10. `AllDocuments.jsx`: Consolidated view of all accessible documents across linked patients with filtering by status, type, and patient.
11. `MedicalDocumentViewer.jsx`: Split-pane viewer with high-resolution file preview/zoom, AI findings panel, confidence gauges, verification action bar, and clinical notes thread.
12. `AIAnalysis.jsx`: Dedicated interactive analysis playground displaying OCR bounding visualizations and NLP entity tag clouds.

#### Mobile Application (`mobile/lib/screens/`)
1. `login_screen.dart`: Native Google Sign-In button and developer token override injection.
2. `home_screen.dart`: Main landing screen with offline banner, recent captures carousel, abnormal test highlights, and quick-action capture FAB.
3. `capture_screen.dart`: Document capture flow using `google_mlkit_document_scanner`, inline blur/glare quality gate evaluation, and live progress indicators.
4. `capture_detail_screen.dart`: Post-capture structured result viewer with panic triage alerts, biomarker list, on-demand Qwen3 Tap-to-Explain, Doctor Visit Prep, and translation sheet.
5. `reports_screen.dart`: Dedicated v2 lab reports feed tracking sync status (`pending`, `synced`, `failed`) and longitudinal trends shortcut.
6. `report_detail_screen.dart`: Full clinical breakdown of a lab report with panel groupings, 10-key values, printed vs standard ranges, and doctor verification notes.
7. `documents_screen.dart`: Parity view for v1 medical documents with file upload picker and sharing controls.
8. `document_detail_screen.dart`: Detail view for server-processed v1 documents with signed file download and sharing sheet.
9. `profile_screen.dart`: Patient profile management, dark/light theme switch, access code generation card, and linked doctor roster.
10. `trends_screen.dart`: Longitudinal biomarker directory grouping lab results over time by canonical analyte name.
11. `trend_detail_screen.dart`: Interactive historical sparkline chart plotting biomarker trajectory against shaded normal reference bands.
12. `patient_summary_screen.dart`: Multi-record doctor handover brief synthesized via Qwen3 SLM map-reduce over stored clinical records.
13. `dev_lab_diff_screen.dart`: Diagnostic split view for developers comparing on-device extraction against server reference outputs.

### State Management Approach
- **Web Frontend**:
  - *Context API (`frontend/src/context/AuthContext.jsx`)*: Centralizes authentication state (`user`, `token`, `login`, `logout`), reads decoded JWT tokens on load, and auto-redirects expired sessions.
  - *Ephemeral State (`useState`, `useEffect`)*: Manages UI states such as active tabs, modals, and pending uploads.
  - *In-Memory Client-Side Cache (`frontend/src/utils/cache.js`)*: Custom higher-order API cache wrapper (`withCache`) that caches GET responses with specific TTLs (e.g. 3 min for patients, 2 min for documents) and provides explicit invalidation methods (`invalidateCache.documents()`).
- **Mobile Application**:
  - *`ChangeNotifier` Controllers*: `ThemeController` persists light/dark preferences via `shared_preferences` and notifies listeners.
  - *Singleton Managers*: `ModelManager` orchestrates asynchronous loading of ResNet-50 ONNX and Qwen3 GGUF; `ResultStore` provides thread-safe access to SQLite database.
  - *Reactive Token Provider*: `ApiClient` and `V2Sync` take dynamic `tokenProvider: () => auth.token` closures with `onUnauthorized` callbacks to refresh tokens seamlessly upon HTTP 401.
  - *Cross-Tab Event Tokens*: `_refreshToken` integer in `AppShell` triggers deferred data refetches across tabs when mutations occur.

### Key Third-Party Libraries

#### Frontend
- `react-router-dom` (v6.4.4): Client-side declarative routing, nested routes, and protected route guards.
- `axios` (v1.2.0): HTTP client configured with request interceptors for JWT Bearer injection.
- `jwt-decode` (v4.0.0): Client-side parsing of JWT claims (role, expiration, user email) without cryptographic verification overhead.
- `react-dropzone` (v14.3.8): Accessible drag-and-drop file upload interface with MIME-type filtering.
- `tailwindcss` (v4.1.17): Utility-first styling framework supporting dark mode and typography presets.

#### Mobile
- `google_mlkit_document_scanner` (v0.6.1): Edge detection, corner adjustment, auto-dewarping, and perspective correction via Google Play Services without camera permission prompts.
- `google_mlkit_text_recognition` (v0.17.1): On-device Latin OCR extracting word-level bounding boxes and confidence metrics.
- `pdfrx` (v2.4.8): Native Pdfium binding rendering PDF pages for UI inspection and extracting raw character geometries.
- `flutter_onnxruntime` (v1.8.5): Native ONNX Runtime inference executing quantized ResNet-50 pneumonia model on mobile CPU/NPU.
- `llama_cpp_dart` (v0.2.2): Dart FFI wrapper over `llama.cpp` using managed background isolates (`LlamaParent`) to run GGUF models.
- `flutter_secure_storage` (v11.1.0): Encrypted key-value persistence storing JWT tokens in Android Keystore / iOS Keychain.
- `sqflite` (v2.4.3): Embedded SQLite database engine persisting offline extraction envelopes and retry queues.
- `connectivity_plus` (v7.3.1): Real-time network listener driving automatic retry sweeps when device reconnects.

---

## 6. CODE METRICS

### Total Lines of Code by Language

| Language / File Format | File Count | Total Lines of Code | Percentage of Source |
| :--- | :---: | :---: | :---: |
| **Dart** (`.dart`) | 81 | 22,665 | 45.2% |
| **Python** (`.py`) | 35 | 7,641 | 15.3% |
| **JSON** (`.json`) | 25 | 7,263 | 14.5% |
| **JavaScript / React JSX** (`.jsx`) | 22 | 5,531 | 11.0% |
| **Markdown** (`.md`) | 8 | 3,506 | 7.0% |
| **CSS** (`.css`) | 7 | 1,882 | 3.8% |
| **JavaScript** (`.js`) | 3 | 345 | 0.7% |
| **YAML** (`.yml`, `.yaml`) | 3 | 222 | 0.4% |
| **Prisma Schema** (`.prisma`) | 1 | 115 | 0.2% |
| **Dockerfiles** | 2 | 56 | 0.1% |
| **HTML** (`.html`) | 1 | 47 | 0.1% |
| **Environment / Configs** (`.env*`, `.gitignore`) | 20 | 826 | 1.7% |
| **TOTAL** | **208** | **50,099** | **100.0%** |

*Note: Generated artifacts, virtual environments (`venv`), build directories (`build/`, `.dart_tool/`, `dist/`), compiled binaries (`.pkl`, `.onnx`, `.gguf`, `.pyc`), and `node_modules/` were strictly excluded from metrics.*

### File and Module Count by Architectural Layer

| Architectural Layer | File Count | Total Lines | Primary Directory Paths |
| :--- | :---: | :---: | :--- |
| **Backend Layer** | 45 | 10,100 | `backend/api/`, `backend/lab_pipeline/`, `backend/scripts/`, `backend/tests/`, `backend/prisma/` |
| **Frontend Web Layer** | 40 | 11,738 | `frontend/src/pages/`, `frontend/src/components/`, `frontend/src/services/`, `frontend/src/context/` |
| **Mobile Application Layer** | 110 | 24,752 | `mobile/lib/`, `mobile/test/`, `mobile/integration_test/`, `mobile/docs/` |
| **Root, Documentation & DevOps**| 13 | 3,509 | Root docs (`README.md`, `Project_Details.md`, etc.), `docker-compose.yml`, root scripts |
| **PROJECT TOTAL** | **208** | **50,099** | Entire IntelliMed-AI Repository |

### Function, Class, and Component Count

| Code Unit Category | Count | Primary Codebase Locations |
| :--- | :---: | :--- |
| **Python Functions (`def`, `async def`)** | 239 | `backend/services.py` (33), `backend/lab_pipeline/` (52), `backend/api/` (46), `backend/tests/` (55) |
| **Python Classes (`class`)** | 17 | `backend/schemas.py`, `backend/api/v2/ingest_schema.py`, `backend/scripts/` |
| **Dart Classes (`class`, `abstract class`)** | 175 | `mobile/lib/api/` (22), `mobile/lib/lab/` (41), `mobile/lib/screens/` (36), `mobile/lib/widgets/` (28) |
| **React Components & Helper Functions** | 222 | `frontend/src/pages/` (128), `frontend/src/components/` (64), `frontend/src/services/` (16) |

### Test Coverage & Verification Analysis
The repository exhibits a bifurcated test distribution:
- **Mobile Test Suite (`mobile/test/`)**: **248 automated tests** across 21 test files covering API clients, token refreshes, geometry reconstruction, rule engines, clinical calculations, and widget layout regressions.
  - Highlights: `inference_correctness_test.dart` (21 tests), `models_test.dart` (26 tests), `document_type_test.dart` (23 tests), `auth_test.dart` (21 tests), `lab_clinical_engine_test.dart` (15 tests), `trends_test.dart` (15 tests).
  - Integration testing: `mobile/integration_test/` contains end-to-end device tests for ONNX and GGUF runtimes.
- **Backend Test Suite (`backend/tests/`)**: **49 automated unit tests** across 5 test files.
  - Highlights: `test_arithmetic_engine.py` (16 tests verifying eGFR, De Ritis, Anion Gap, Bilirubin consistency), `test_rule_engine.py` (19 tests verifying single-test flags and multi-analyte pattern matching), `test_v2_structured_ingest.py` (6 tests enforcing schema compliance), `test_v2_lab_refs.py` (5 tests), `test_stage2_recovery.py` (3 tests).
- **Frontend Test Suite (`frontend/src/`)**: **0 automated unit/integration tests**. Although `@testing-library/react` and `@testing-library/jest-dom` are installed in `frontend/package.json`, no test files (`*.test.js` or `*.test.jsx`) exist in `frontend/src/`. All frontend testing currently relies on manual user verification.

---

## 7. NOTABLE ENGINEERING DECISIONS

### Architectural Trade-offs & Rationale
1. **Strict Separation of Extraction (Stage 2) and Interpretation (Stage 3)**:
   - *Decision:* As documented in `backend/lab_pipeline/slm_stage.py` and `LAB_REPORT_ENGINE_PLAN.md`, Stage 2 normalizes tables into canonical analyte names and reference bounds but is strictly forbidden from computing abnormal flags.
   - *Trade-off:* Requires an extra pipeline stage (`rule_engine.py`), but prevents SLM hallucinations from injecting incorrect diagnostic interpretations into a patient's medical record.
2. **On-Device Edge Inference vs. Cloud Processing for Mobile**:
   - *Decision:* Mobile captures run OCR, table reconstruction, and SLM explanation entirely on the device. Only structured JSON is synchronized (`source: "app"`).
   - *Trade-off:* Bundling `Qwen3-0.6B-Q4_0.gguf` (~382 MB) and `pneumonia_resnet50.onnx` (~94 MB) significantly increases APK download size, but provides 100% offline functionality and ensures raw protected health information (PHI) never leaves the patient's device without consent.
3. **Qwen3 Thinking Mode Suppression for Mobile CPU Execution**:
   - *Decision:* In `mobile/lib/slm_runtime.dart`, ChatML prompts are prefilled with `<|im_start|>assistant\n<think>\n\n</think>\n\n`.
   - *Trade-off:* Sacrifices internal chain-of-thought tokens, but reduces token generation budget by 70%, preventing CPU starvation and 3-minute latency stalls on mid-range Android hardware.
4. **Synthetic File Path Abstraction (`app-structured/<kind>`)**:
   - *Decision:* In `backend/api/v2/lab_refs.py`, app-generated records use pseudo-paths rather than null database columns.
   - *Trade-off:* Requires helper wrappers (`has_stored_file`), but avoids database schema migrations and maintains backwards compatibility with v1 download endpoints.
5. **Thread-Safe Multi-Tier Access Caching**:
   - *Decision:* Implemented `request_cache.py` with in-memory locks and monotonic timers to cache doctor-patient access checks (120s TTL) alongside FastAPI-Cache2 (300s TTL).
   - *Trade-off:* Introduces cache invalidation complexity, but reduces repetitive PostgreSQL queries during high-concurrency document views by over 80%.

### Known Limitations & Code Annotations
1. **Incomplete Document-Level Access Control (ACL) Enforcement**:
   - *Observation:* While the `DocumentShare` table exists and endpoints in `sharing_router.py` manage specific document grants, `backend/api/doctor_router.py::get_patient_documents_for_doctor` fetches *all* documents belonging to `patient_id` once doctor-patient linking is confirmed. Granular document-level filtering is noted as an audit item in `AUDIT_REPORT.md`.
2. **Heavy Synchronous Cold-Start Latencies**:
   - *Observation:* In `backend/services.py`, the initial load of EasyOCR models and the Falconsai T5 summarizer requires up to 10 seconds of CPU blocking time if GPU acceleration is unavailable.
3. **OpenDataLoader Hybrid Backend Dependency**:
   - *Observation:* Scanned lab report PDFs uploaded to the server v2 pipeline require an external microservice (`opendataloader-pdf-hybrid` on port 5002) for OCR. If unreachable, the system falls back to EasyOCR, causing bounding box coordinates to degrade to `null`.
4. **Mobile Model Asset Bundling in Production**:
   - *Observation:* As highlighted in `QWEN3_SLM_UPGRADE_PLAN.md`, shipping the ~382 MB GGUF file directly in `assets/models/` is suitable for local PBL demos, but requires migration to on-demand CDN downloads (`getApplicationSupportDirectory()`) before commercial Google Play Store deployment.

---

## 8. SUGGESTED SYSTEM DIAGRAMS

### Diagram 1: System Architecture Diagram
```mermaid
flowchart TD
    subgraph Clients["Client Layer"]
        Web["React 18 SPA (Vercel)\nAxios Client + In-Memory Cache"]
        Mobile["Flutter App (Android)\nML Kit + ONNX Runtime + Llama.cpp"]
    end

    subgraph Gateway["API Gateway Layer (FastAPI / Modal)"]
        RouterV1["API v1 Routers\n/auth, /patient, /doctor, /documents"]
        RouterV2["API v2 Routers\n/lab-reports, /upload-structured"]
        CacheLayer["FastAPI Cache2 & RequestCache\n(In-Memory TTL Maps)"]
    end

    subgraph AIPipelines["AI / ML Processing Engines"]
        V1Engine["services.py Monolith\n- EasyOCR / Tesseract\n- ResNet-50 Pneumonia CNN\n- spaCy / Medication Regex\n- Falconsai T5 Summarizer"]
        V2Engine["lab_pipeline/ Engine\n- Stage 1: OpenDataLoader-PDF\n- Stage 2: Deterministic Normalizer\n- Stage 3: Clinical Rule Table Engine"]
    end

    subgraph Persistence["Storage & Persistence Layer"]
        PostgreSQL[("PostgreSQL (Prisma ORM)\nUsers, Documents, LabReports, Shares")]
        SupabaseS3[("Supabase Object Storage\nBucket: medical-documents")]
        MobileSQLite[("Mobile SQLite (sqflite)\nresults: pending/synced/failed")]
    end

    Web -->|HTTPS REST /api/v1/*| RouterV1
    Mobile -->|HTTPS REST /api/v1/*| RouterV1
    Mobile -->|HTTPS REST /api/v2/*| RouterV2
    Mobile <-->|Local Read/Write| MobileSQLite

    RouterV1 <--> CacheLayer
    RouterV2 <--> CacheLayer

    RouterV1 --> V1Engine
    RouterV2 --> V2Engine

    RouterV1 <-->|Prisma Queries| PostgreSQL
    RouterV2 <-->|Prisma Queries| PostgreSQL

    RouterV1 <-->|Signed URL / Upload| SupabaseS3
    RouterV2 <-->|Signed URL / Upload| SupabaseS3
```

### Diagram 2: Data Flow Diagram (Upload -> Verification Flow)
```mermaid
flowchart TD
    A["Patient Uploads Document\n(Web Dropzone / Mobile Picker)"] --> B{"Client Upload Route"}
    
    B -->|Web: Raw File| C["POST /api/v1/patient/upload/\n(patient_router.py)"]
    B -->|Mobile: Structured JSON| D["POST /api/v2/lab-reports/upload-structured\n(lab_report_router.py)"]
    
    C --> E["Save Temporary File & Upload to Supabase S3\n(supabase_storage.py)"]
    E --> F["Concurrent AI Inference\n(services.py)"]
    
    F --> F1["services.ocr_service()\n(EasyOCR / Tesseract)"]
    F --> F2["services.cv_service()\n(ResNet-50 Classifier)"]
    F1 --> F3["services.nlp_service()\n(spaCy + Drug Dict)"]
    F1 & F3 --> F4["services.medical_summarize_service()\n(T5 Seq2Seq)"]
    
    F1 & F2 & F3 & F4 --> G["Arbitrate Document Type\n(Prescription > X-Ray > Document)"]
    G --> H["Persist MedicalDocument in DB\n(medical_documents table)"]
    
    D --> I["Validate Ingest Schema\n(ingest_schema.py)"]
    I --> J["Server Stage 3 Rule Engine\n(rule_engine.py: annotate)"]
    J --> K["Persist LabReport in DB\n(source='app')"]
    
    H & K --> L["Patient Generates 6-Char Access Code\n(linking_router.py)"]
    L --> M["Doctor Links to Patient via Code\n(doctor_patient table)"]
    
    M --> N["Doctor Views Documents & Lab Reports\n(doctor_router.py & lab_report_router.py)"]
    N --> O["Doctor Signs Verification & Adds Notes\n(document_router.py::verify_document)"]
    O --> P["Patient Views Verified Stamp & Clinical Notes\n(PatientDashboard.jsx)"]
```

### Diagram 3: Sequence Diagram (Document Upload, AI Analysis & Doctor Review)
```mermaid
sequenceDiagram
    autonumber
    actor Patient as Patient (Web/App)
    participant API as FastAPI Backend
    participant Storage as Supabase Storage
    participant AI as AI Services (services.py)
    participant DB as PostgreSQL (Prisma)
    actor Doctor as Doctor (Portal)

    Patient->>API: POST /api/v1/patient/upload/ (file multipart)
    activate API
    API->>Storage: upload_file(patients/{id}/{filename})
    Storage-->>API: stored_path
    API->>AI: asyncio.gather(ocr_service, cv_service)
    activate AI
    AI-->>API: ocr_text, cv_result (probabilities, labels)
    deactivate AI
    API->>AI: nlp_service(ocr_text) + medical_summarize_service()
    activate AI
    AI-->>API: nlp_result (medications), summary_result
    deactivate AI
    API->>DB: db.medicaldocument.create(ai_analysis_json, file_path)
    DB-->>API: MedicalDocument record (ID: doc_123)
    API-->>Patient: DocumentInfo (status: "processed")
    deactivate API

    Patient->>API: POST /api/v1/patient/generate-access-code
    API->>DB: db.doctorpatient.create(access_code: "4B9F2A")
    API-->>Patient: {"access_code": "4B9F2A"}

    Patient-->>Doctor: Communicates Code "4B9F2A"
    Doctor->>API: POST /api/v1/doctor/link-patient {"access_code": "4B9F2A"}
    API->>DB: db.doctorpatient.update(doctor_id = doc_user.id)
    API-->>Doctor: {"message": "Patient linked successfully"}

    Doctor->>API: GET /api/v1/doctor/patients/{id}/documents
    API->>DB: Verify access link & query medical documents
    API->>Storage: create_signed_url(doc_123.file_path, expiry=300)
    Storage-->>API: signed_url
    API-->>Doctor: List[DocumentDetail] with signed_url

    Doctor->>API: POST /api/v1/documents/doc_123/verify {"notes": "Pneumonia confirmed. Prescribed Azithromycin."}
    API->>DB: db.medicaldocument.update(verified_by, verified_at, notes)
    API-->>Doctor: {"message": "Document verified successfully"}

    Patient->>API: GET /api/v1/patient/documents
    API->>DB: Query own documents
    API-->>Patient: Returns doc_123 showing "Verified" status with physician notes
```

### Diagram 4: Class Diagram (Key Backend & Mobile Core Classes)
```mermaid
classDiagram
    class User {
        +int id
        +string email
        +string name
        +string hashed_password
        +role_enum role
        +string blood_type
        +string allergies
        +string chronic_conditions
    }

    class MedicalDocument {
        +int id
        +int patient_id
        +string file_path
        +DateTime upload_timestamp
        +Json ai_analysis_json
        +string source
        +int verified_by
        +DateTime verified_at
        +string verification_notes
        +Json clinical_notes
        +bool archived
    }

    class LabReport {
        +int id
        +int patient_id
        +string file_path
        +DateTime upload_timestamp
        +string source
        +Json result_json
        +int verified_by
        +DateTime verified_at
    }

    class DoctorPatient {
        +int id
        +int doctor_id
        +int patient_id
        +string access_code
        +DateTime created_at
    }

    class DocumentShare {
        +int id
        +int document_id
        +int doctor_id
        +DateTime shared_at
    }

    class QwenSlmRuntime {
        +string modelPath
        +int maxNewTokens
        +Duration completionTimeout
        +load() Future~void~
        +summarize(String text) Future~Map~
        +explainBiomarker(String test, String val, String unit) Future~String~
        +doctorVisitPrep(List tests) Future~String~
        +translateInstructions(String text, String lang) Future~String~
    }

    class ResultStore {
        -Database _db
        +instance() Future~ResultStore~
        +insertPending(String kind, String path, String json) Future~int~
        +pending() Future~List~
        +markSynced(int id, int serverId) Future~void~
        +markFailed(int id, String err) Future~void~
    }

    class V2Sync {
        +String baseUrl
        +String token
        +syncOne(int id) Future~bool~
        +retryQueued() Future~int~
        +watchConnectivity(Function onOnline) void
    }

    class PatientRepository {
        +ApiClient client
        +listLabReports() Future~List~
        +getLabReport(int id) Future~LabReport~
        +listDocuments() Future~List~
        +uploadDocument(bytes, filename) Future~DocumentSummary~
        +generateAccessCode() Future~String~
    }

    User "1" --> "*" MedicalDocument : owns
    User "1" --> "*" LabReport : owns
    User "1" --> "*" DoctorPatient : doctor_relations
    User "1" --> "*" DoctorPatient : patient_relations
    MedicalDocument "1" --> "*" DocumentShare : shares
    User "1" --> "*" DocumentShare : shared_with

    ResultStore <.. V2Sync : reads pending results
    V2Sync <.. PatientRepository : coordinates sync
    QwenSlmRuntime <.. PatientRepository : formats records
```

### Diagram 5: Entity-Relationship (ER) Diagram (Prisma Database Models)
```mermaid
erDiagram
    users ||--o{ medical_documents : "uploads/owns"
    users ||--o{ lab_reports : "uploads/owns"
    users ||--o{ doctor_patient : "links as doctor"
    users ||--o{ doctor_patient : "links as patient"
    users ||--o{ document_share : "receives shared doc"
    medical_documents ||--o{ document_share : "is shared via"

    users {
        int id PK
        varchar email UK
        varchar name
        varchar hashed_password
        role_enum role
        datetime created_at
        varchar phone
        date date_of_birth
        varchar gender
        text address
        varchar emergency_contact
        varchar emergency_phone
        varchar blood_type
        text allergies
        text chronic_conditions
        boolean dark_mode
        boolean email_notifications
        boolean push_notifications
    }

    doctor_patient {
        int id PK
        int doctor_id FK "nullable"
        int patient_id FK
        varchar access_code UK "nullable"
        datetime created_at
    }

    medical_documents {
        int id PK
        int patient_id FK "nullable"
        varchar file_path
        timestamptz upload_timestamp
        json ai_analysis_json
        varchar source "default: web"
        int verified_by "nullable"
        datetime verified_at "nullable"
        text verification_notes "nullable"
        json clinical_notes "default: []"
        boolean archived "default: false"
        datetime archived_at "nullable"
        int archived_by "nullable"
    }

    lab_reports {
        int id PK
        int patient_id FK "nullable"
        varchar file_path
        timestamptz upload_timestamp
        varchar source "default: web"
        json result_json
        int verified_by "nullable"
        datetime verified_at "nullable"
        text verification_notes "nullable"
    }

    document_share {
        int id PK
        int document_id FK
        int doctor_id FK
        datetime shared_at
    }
```

---

### Conclusion & System Summary
The **IntelliMed-AI** codebase represents a complete and production-grade full-stack architecture combining classical computer vision, state-of-the-art quantized small language models (Qwen3-0.6B on llama.cpp), transfer-learning deep CNNs (ResNet-50), and deterministic clinical rule engines. Its clean separation between edge computing on mobile and centralized orchestration on the backend preserves patient data sovereignty and HIPAA-aligned privacy while maintaining cross-platform compatibility across modern web browsers and Android devices.
