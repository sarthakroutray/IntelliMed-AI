# IntelliMed-AI: Code & Product Audit Report

## 1. System Overview
**IntelliMed-AI** is a healthcare platform bridging the gap between medical diagnostic data and patient-doctor communication through an AI-driven pipeline.

### Tech Stack
- **Frontend**: React (Vite), Tailwind CSS, Vercel (Hosting).
- **Backend**: FastAPI, Prisma (PostgreSQL), Modal (Serverless AI Orchestration).
- **Storage**: Supabase Buckets.
- **AI Engine**: EasyOCR, PyMuPDF, Spacy, Transformers (Medical T5), Torch (Pneumonia Detection).

---

## 2. Technical Foundation & Architecture
- **Backend Orchestration**: Uses **Modal** for serverless scaling of GPU-heavy tasks (OCR/Inference). This is a strong choice for high-availability AI.
- **Data Layer**: Prisma provides a type-safe interface to PostgreSQL, though some relational constraints (like `DocumentShare`) are not yet fully enforced in the API logic.
- **AI Pipeline**: A multi-stage monolith in `services.py`. While functional, it is a risk hotspot for memory overhead and debugging complexity.

---

## 3. High-Priority Risk Hotspots (Status Updated: 2026-04-10)

### 🚨 Security: Critical Vulnerabilities (Resolved)
1. **OAuth Verification Hardened**: `backend/google_oauth.py` now verifies Google ID token signature and claims server-side via Google's verification flow.
2. **Hardcoded Secrets Removed**: Auth and registration secrets were moved to environment variables (`SECRET_KEY`, `DOCTOR_ACCESS_CODE`, `ADMIN_PASSWORD`, `ADMIN_EMAIL`).
3. **Storage Exposure Mitigated**: Supabase document access now uses short-lived signed URLs instead of long-lived public URLs.

### 🐛 Reliability: Implementation Bugs (Resolved)
1. **Shadowing Bug Fixed**: Download flow in `MedicalDocumentViewer.jsx` now uses `window.document` for DOM operations.
2. **API Contract Aligned**: `verify_document` and `add_clinical_note` now accept JSON body payloads (with query fallback compatibility).
3. **Analyze Action Fixed**: Patient dashboard Analyze button now calls `analyzeDocument` before refreshing document data.

---

## 4. Feature Roadmap (Top 11 Recommendations)

### I. Security & Compliance (Low Effort / High Impact)
1. **Document-Level ACL**: Enforce `DocumentShare` logic so doctors can *only* see specifically shared records.
2. **PII Redaction**: Automatically blur Names/Birthdays in the UI before "Analysis" for privacy compliance.

### II. AI & Analytics ("Portfolio Wow-Factor")
3. **Clinical Document Timeline**: A chronological view of patient history vs. just a list of files.
4. **Interactive Medical Glossary**: Click on complex terms in the AI summary to see simple definitions.
5. **Comparison Engine**: Compare an old X-ray analysis with a new one to highlight "Stability" vs. "Progression."
6. **Prescription Conflict Check**: Flag potential drug-drug interactions between multiple uploaded prescriptions.

### III. UX & Workflow (Product High-Impact)
7. **Batch Uploading**: allow dragging multiple labs at once.
8. **Doctor "One-Shot" Review**: A unified view for doctors to verify multiple AI flags in a single click.
9. **Offline Viewer**: Cache processed summaries using Service Workers for quick mobile access.
10. **Patient Q&A Bot**: A "Ask about this report" side-chat powered by the existing T5 model.
11. **Print-Optimized Reports**: A one-page PDF summary for patients to bring to physical appointments.

---

## 5. Next Steps / Sprint Plan
- [x] **Day 1**: Fix Google OAuth and Shadowing Bug.
- [x] **Day 2**: Align API contracts for "Verify" and "Add Note."
- [ ] **Day 3**: Implement the "Document Timeline" frontend component.
- [ ] **Day 4**: Enforce Privacy toggles in the database.
