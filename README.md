# IntelliMed-AI

IntelliMed-AI is a full-stack medical document platform that connects patients and doctors with secure sharing and AI-assisted analysis.

The system supports:
- Role-based authentication (patient, doctor, admin)
- Patient-doctor linking with access codes
- Medical document upload, sharing, review, and archival
- AI pipelines for OCR, medical NLP extraction, and chest X-ray classification

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
- ResNet50-based classifier
- Classes: Normal, Bacterial Pneumonia, Viral Pneumonia
- Returns probabilities and a primary classification label

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
- MedicalDocument
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
│  ├─ prisma/
│  ├─ models/
│  ├─ main.py
│  ├─ services.py
│  └─ requirements.txt
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

Generate Prisma client:

```bash
prisma generate
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
- USE_OPENDATALOADER_FOR_PDFS
- OPENDATALOADER_USE_STRUCT_TREE
- OPENDATALOADER_HYBRID
- OPENDATALOADER_HYBRID_URL
- OPENDATALOADER_HYBRID_TIMEOUT

### frontend/.env
- VITE_API_BASE_URL
- VITE_GOOGLE_CLIENT_ID

## 10. API Surface (High-Level)

### Auth
- POST /api/auth/token
- POST /api/auth/google-login
- POST /api/auth/register

### Patient
- POST /api/patient/upload/
- GET /api/patient/documents
- DELETE /api/patient/documents/{document_id}
- GET /api/patient/linked-doctors

### Doctor
- GET /api/doctor/patients
- GET /api/doctor/patients/{patient_id}/documents

### Linking
- POST /api/patient/generate-access-code
- POST /api/doctor/link-patient

### Documents
- GET /api/documents/{document_id}
- POST /api/documents/{document_id}/analyze
- POST /api/documents/{document_id}/verify
- POST /api/documents/{document_id}/notes
- POST /api/documents/{document_id}/archive
- GET /api/documents/{document_id}/download

### Profile
- GET /api/profile
- PUT /api/profile

### Sharing
- POST /api/patient/documents/{document_id}/share/{doctor_id}
- DELETE /api/patient/documents/{document_id}/share/{doctor_id}
- GET /api/patient/documents/{document_id}/shared-doctors

## 11. Testing

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
3. System architecture (frontend, backend, DB, storage, AI)
4. Feature modules (auth, linking, documents, AI analysis)
5. Database design (Prisma schema entities and relations)
6. API design and endpoint mapping
7. AI pipeline details and limitations
8. Security considerations
9. Deployment strategy
10. Testing strategy and results
11. Challenges faced and improvements planned
12. Conclusion

Suggested quantitative items to include in your report:
- Number of API endpoints
- Number of core DB entities
- AI service components (OCR/NLP/CV)
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
- Large generated binaries unless intentionally versioned
