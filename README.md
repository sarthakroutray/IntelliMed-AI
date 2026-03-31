    # IntelliMed-AI

IntelliMed-AI is a comprehensive medical application designed to bridge the gap between patients and doctors. It facilitates secure medical document management, patient-doctor linking, and leverages AI for analyzing medical records.

## Features

### Core Features
- **Role-Based Access Control**: Distinct dashboards for Patients, Doctors, and Admins.
- **Authentication**: Secure login and registration with email/password and Google OAuth support.
- **Patient Dashboard**:
  - Securely upload and store medical documents (PDF, JPEG, DICOM, PNG).
  - View AI-generated analysis of medical records.
  - Manage access permissions for doctors.
  - Share/unshare documents with linked doctors.
- **Doctor Dashboard**:
  - View linked patients and their documents.
  - Access patient medical documents and AI analysis.
  - Verify and sign off on document analysis.
  - Add clinical notes to documents.
- **Patient-Doctor Linking**: Secure linking mechanism using unique access codes.

### AI-Powered Capabilities

#### 📋 Optical Character Recognition (OCR)
- **Multi-pass preprocessing pipeline** for handwritten prescriptions and medical documents
- **Advanced image enhancement**:
  - OpenCV preprocessing: Adaptive thresholding, OTSU binarization, morphological operations, CLAHE contrast enhancement, noise denoising
  - PIL preprocessing: Contrast enhancement, histogram stretching, median filtering, edge enhancement
  - Automatic deskewing (rotation correction for scanned documents)
  - Upscaling for small/low-resolution images
- **Multiple Tesseract PSM modes** for optimal text extraction across document layouts
- **Graceful fallback strategy** with multiple preprocessing variants
- **OCR output cleaning** to remove noise and normalize extracted text
- **OpenDataLoader-powered PDF parsing** for layout-aware prescription/document extraction, with optional hybrid mode support and EasyOCR fallback for scanned or handwritten image-heavy prescriptions

#### 💊 Medical NLP & Prescription Parsing
- **Medical entity recognition** with 150+ common medications (antibiotics, cardiac, diabetes, psychiatric, respiratory, etc.)
- **Structured prescription extraction**:
  - Medication names (brand & generic)
  - Dosages (mg, ml, mcg, g, IU, etc.)
  - Frequencies (once daily, BID, TID, as needed, etc.)
  - Routes of administration (oral, topical, intravenous, inhaled, etc.)
  - Durations (for 7 days, 2 weeks, indefinitely, etc.)
- **General NER** via spaCy for Person, Organization, Date, Location entities
- **Prescription detection heuristic**
- **Medical summary generation** with entity-type counts
- **Regex-based fallback** that works even without spaCy model

#### 🫁 Chest X-Ray Analysis
- **Pneumonia classifier** using fine-tuned ResNet50
- **Classification categories**: Normal, Bacterial Pneumonia, Viral Pneumonia
- **GPU acceleration** with mixed precision (AMP) for faster inference
- **Confidence scores** and probability distribution for each class
- **Clinical recommendations** based on classification results

#### 📊 AI Analysis Dashboard
- **Real-time document analysis** via dedicated `/documents/{id}/analyze` endpoint
- **Comprehensive analysis display**:
  - Classification results with confidence scores
  - Probability distribution charts
  - Extracted prescription details with structured metadata
  - NLP entities with confidence scores and color-coded labels
  - Raw OCR text in collapsible panel
  - Clinical recommendations
- **Doctor verification workflow** with sign-off capability
- **Clinical note annotations** on analyzed documents

## Tech Stack

### Backend
- **Framework**: [FastAPI](https://fastapi.tiangolo.com/) (Python)
- **Database ORM**: [Prisma](https://prisma.io/) (with `prisma-client-py`)
- **Database**: PostgreSQL
- **Authentication**: JWT (JSON Web Tokens) & Google OAuth
- **File Handling**: `python-multipart` for uploads

### AI/ML & Document Processing
- **OCR**: [Tesseract](https://github.com/UB-Mannheim/tesseract) via `pytesseract`
- **Image Processing**: [OpenCV](https://opencv.org/) (`cv2`) for advanced preprocessing
- **NLP**: [spaCy](https://spacy.io/) for named entity recognition
- **Medical Imaging**: [PyTorch](https://pytorch.org/) + [TorchVision](https://pytorch.org/vision/) for pneumonia classification
- **Image Handling**: [Pillow](https://pillow.readthedocs.io/) (PIL)
- **Numerical Computing**: [NumPy](https://numpy.org/)

### Frontend
- **Framework**: [React](https://reactjs.org/) with [Vite](https://vitejs.dev/)
- **Styling**: [Tailwind CSS](https://tailwindcss.com/)
- **Routing**: React Router
- **HTTP Client**: Axios

## Deployment

- Frontend: Vercel from `frontend/`
- Backend: Modal from `backend/modal_app.py` using `backend/Dockerfile`
- Setup guide: `DEPLOYMENT.md`

## Getting Started

### Prerequisites
- Node.js (v16+)
- Python (v3.8+)
- PostgreSQL Database

### Backend Setup

1. Navigate to the backend directory:
   ```bash
   cd backend
   ```

2. Create and activate a virtual environment:
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

4. **[Optional] Install Tesseract OCR** for handwritten prescription support:
   - **Ubuntu/Debian**: `sudo apt-get install tesseract-ocr`
   - **macOS**: `brew install tesseract`
   - **Windows**: Download from [UB Mannheim](https://github.com/UB-Mannheim/tesseract/wiki)
   - **Note**: Without Tesseract, OCR will gracefully fall back to mock results

5. **[Optional] Download spaCy NLP model** for enhanced entity recognition:
   ```bash
   python -m spacy download en_core_web_sm
   ```
   - Without this, NLP will still work using regex-based extraction

6. Set up environment variables:
   - Create a `.env` file in the `backend` directory.
   - Required variables: `DATABASE_URL`, `DIRECT_URL`, `SECRET_KEY`, `GOOGLE_CLIENT_ID`
   - Example:
     ```
     DATABASE_URL=postgresql://user:password@localhost:5432/intellimed
     DIRECT_URL=postgresql://user:password@localhost:5432/intellimed
     SECRET_KEY=your-secret-key-here
     GOOGLE_CLIENT_ID=your-google-client-id
     MAX_CONCURRENT_HEAVY=2
     ```

7. Generate Prisma client:
   ```bash
   prisma generate
   ```

8. Run the server:
   ```bash
   uvicorn main:app --reload
   ```
   The API will be available at `http://localhost:8000`.

### Frontend Setup

1. Navigate to the frontend directory:
   ```bash
   cd frontend
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Run the development server:
   ```bash
   npm run dev
   ```
   The application will be available at `http://localhost:5173` (or the port shown in the terminal).

## Project Structure

- `backend/`: FastAPI application, API routes, and database schema.
- `frontend/`: React application, components, and pages.
## AI Features & Usage

### Document Upload & Analysis Workflow

1. **Patient uploads document** → `POST /api/patient/upload/`
   - Supports: PDF, JPEG, PNG, DICOM
   - File stored in `backend/uploads/`

2. **Trigger AI analysis** → `POST /api/documents/{document_id}/analyze`
   - Three AI services run in parallel:
     - **OCR Service**: Extracts text from documents (prescriptions, medical notes, etc.)
     - **CV Service**: Analyzes X-ray images for pneumonia classification
     - **NLP Service**: Extracts medical entities and prescriptions from OCR text

3. **Analysis results returned** with:
   ```json
   {
     "ocr_result": "Patient prescribed Amoxicillin 500mg...",
     "cv_result": {
       "classification": "Normal",
       "confidence": 0.92,
       "probabilities": {...},
       "recommendation": "..."
     },
     "nlp_result": {
       "is_prescription": true,
       "medications": ["Amoxicillin"],
       "prescriptions": [{
         "medication": "Amoxicillin",
         "dosage": "500mg",
         "frequency": "twice daily",
         "duration": "7 days"
       }],
       "entities": [...]
     }
   }
   ```

4. **Doctor reviews & verifies** → `POST /api/documents/{document_id}/verify`

### Key API Endpoints

#### Documents
- `GET /api/documents/{document_id}` - Get document with AI analysis
- `POST /api/documents/{document_id}/analyze` - Run AI analysis
- `POST /api/documents/{document_id}/verify` - Doctor verification
- `POST /api/documents/{document_id}/notes` - Add clinical notes
- `POST /api/documents/{document_id}/archive` - Archive document

#### Patient Management
- `POST /api/patient/upload/` - Upload medical document
- `GET /api/patient/documents` - Get patient's documents
- `POST /api/patient/documents/{id}/share/{doctor_id}` - Share with doctor

#### Doctor Management
- `GET /api/doctor/patients` - Get linked patients
- `GET /api/doctor/patients/{patient_id}/documents` - Get patient documents

### AI Model Details

#### Pneumonia Classifier
- **Model**: ResNet50 fine-tuned on chest X-ray dataset
- **Classes**: Normal, Bacterial Pneumonia, Viral Pneumonia
- **Location**: `backend/models/best_model_optimized.pkl`
- **Inference**: GPU-accelerated with mixed precision (AMP)

#### OCR Pipeline
- **Multi-pass strategy** with 15+ preprocessing variants
- **Optimized for**: Handwritten prescriptions, low-quality scans, skewed documents
- **Supports**: Multiple languages via Tesseract

#### NLP Medical Entity Extraction
- **Medication Database**: 150+ common drugs (antibiotics, cardiac, psychiatric, etc.)
- **Detects**: Medications, dosages, frequencies, routes, durations
- **Fallback**: Works without spaCy using regex-based extraction

## Performance & Deployment

### Concurrency Management
- Maximum 2 concurrent heavy AI tasks by default (configurable via `MAX_CONCURRENT_HEAVY`)
- Prevents resource exhaustion under load
- Thread-safe model loading with locks

### GPU Support
- Automatic GPU detection and usage
- Falls back to CPU if GPU unavailable
- Mixed precision (AMP) for faster inference on compatible GPUs

### Error Handling
- Graceful degradation: Services work even without optional dependencies
- OCR without Tesseract → uses mock results
- NLP without spaCy model → uses regex fallback
- CV without GPU → uses CPU inference

---

## Running & Testing the Application

### Quick Start (Both Services)

**Terminal 1 - Backend:**
```bash
cd backend
python -m venv venv
# On Windows:
venv\Scripts\activate
# On macOS/Linux:
source venv/bin/activate

pip install -r requirements.txt
uvicorn main:app --reload
# Server runs at http://localhost:8000
# API docs at http://localhost:8000/docs
```

**Terminal 2 - Frontend:**
```bash
cd frontend
npm install
npm run dev
# App runs at http://localhost:5173
```

Open browser to `http://localhost:5173` → You're all set! 🚀

---

## Testing All Functionalities

### 1. Authentication & Registration

**Via UI:**
1. Go to `http://localhost:5173/login`
2. Click **"Register"** tab
3. **Test Patient Registration:**
   - Email: `patient1@example.com`
   - Password: `SecurePass123!`
   - Role: **Patient**
   - Click Register
4. **Test Doctor Registration:**
   - Email: `doctor1@example.com`
   - Password: `SecurePass123!`
   - Role: **Doctor**
   - Click Register

**Via API (Postman/curl):**
```bash
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "patient1@example.com",
    "password": "SecurePass123!",
    "role": "patient"
  }'
```

### 2. Patient-Doctor Linking

**Patient Side:**
1. Login as patient (`patient1@example.com`)
2. Go to **Dashboard** → **Link Doctor** button
3. Ask for access code (shown in generate access code modal)

**Doctor Side:**
1. Login as doctor (`doctor1@example.com`)
2. Go to **Dashboard** → **Link Patient** button
3. Paste the access code from patient
4. Successfully linked! ✅

### 3. Document Upload

**Via UI:**
1. Login as patient
2. Go to **Patient Dashboard**
3. **Drag & drop** a test image/PDF OR click **"Upload Document"**
4. Select:
   - File: `sample_xray.jpg` (any chest X-ray image)
   - Type: **DICOM** or **X-Ray**
5. Document appears in **My Documents** list ✅

**Supported Formats**: PDF, JPG, JPEG, PNG, DICOM

**Via API:**
```bash
curl -X POST http://localhost:8000/api/patient/upload/ \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@/path/to/xray.jpg"
```

### 4. AI Analysis - Full Pipeline Testing

**Test Case A: X-Ray Pneumonia Classification**
1. Login as patient
2. Upload a chest X-ray image
3. Go to **AI Analysis** dashboard
4. Find your uploaded document in **Pending** section
5. Click **"Analyze Now"** button
6. Wait for analysis (takes 10-30 seconds)
7. **Verify results display:**
   - ✅ Classification (Normal/Bacterial/Viral Pneumonia)
   - ✅ Confidence score (0-100%)
   - ✅ Probability bars for each class
   - ✅ Clinical recommendation

**Test Case B: Prescription Extraction (Handwritten)**
1. Create a test image with handwritten prescription text:
   ```
   Amoxicillin 500mg
   Twice daily for 7 days
   Take with food
   ```
2. Upload the image
3. Click **"Analyze Now"**
4. **Verify prescription parsing:**
   - ✅ Medication detected: "Amoxicillin"
   - ✅ Dosage extracted: "500mg"
   - ✅ Frequency identified: "Twice daily"
   - ✅ Duration recognized: "7 days"
   - ✅ Structured data in **Prescription Details** section

**Test Case C: OCR Text Extraction**
1. Upload a document with mixed typed + handwritten text
2. Run analysis
3. Expand **"OCR Extracted Text"** section
4. **Verify:**
   - ✅ Text extracted with minimal noise
   - ✅ Line breaks preserved
   - ✅ Medical terms properly recognized

### 5. Testing AI Services Directly (Optional)

**Via FastAPI Docs:**
1. Navigate to `http://localhost:8000/docs`
2. Find `POST /api/documents/{document_id}/analyze`
3. Click "Try it out"
4. Enter a document ID from your uploads
5. Click "Execute"
6. **View full JSON response** with:
   - `ocr_result`: Raw extracted text
   - `cv_result`: X-ray classification
   - `nlp_result`: Extracted medications and entities

### 6. Doctor Workflow - Verification & Notes

**As Doctor:**
1. Login as doctor (linked to patient)
2. Go to **AI Analysis** or **Doctor Dashboard**
3. Select a patient's analyzed document
4. **Click "View Document"** to open document viewer
5. **Verify & Sign Off:**
   - Click **"Verify & Sign Off"** button
   - Analysis is verified ✅
6. **Add Clinical Note:**
   - Click **"Add Clinical Note"** button
   - Add your clinical observations
   - Save ✅

### 7. Document Sharing

**Patient Side:**
1. Go to **Patient Dashboard**
2. Find a document in your list
3. Click document → expand **"Share"** modal
4. Toggle doctors on/off to share
5. Document appears in doctor's access list

**Doctor Side:**
1. Navigate to **Doctor Dashboard** → **View Patient Documents**
2. Only **shared documents** are visible
3. Can view analysis and add clinical notes

---

## Testing With Sample Data

### Minimal Test Flow (5 minutes)
1. Register patient: `patient@test.com` / `Pass123!`
2. Register doctor: `doctor@test.com` / `Pass123!`
3. Link patient & doctor using access code
4. Patient uploads any `.jpg` image
5. Click "Analyze Now"
6. Wait for analysis (uses mock/real results)
7. Doctor verifies document
8. ✅ Complete workflow tested

### Comprehensive Test Flow (30 minutes)
1. Repeat minimal flow
2. **Upload multiple document types:**
   - X-ray image → verify pneumonia classification
   - Prescription photo → verify medication extraction
   - Text document → verify OCR
3. **Test NLP:** Upload image with text like:
   ```
   Patient Name: John Doe
   Prescribed: Lisinopril 10mg daily, Metformin 500mg BID
   Allergies: Penicillin
   Follow-up: 2 weeks
   ```
   - Verify medications extracted
   - Verify dosages recognized
   - Verify frequencies identified
4. **Test Doctor workflow:**
   - Add multiple clinical notes
   - Verify & sign off
   - View document history
5. **Test document sharing:**
   - Share/unshare with different doctors
   - Verify access control

---

## API Testing with Postman/cURL

### Authentication Flow
```bash
# Register
curl -X POST http://localhost:8000/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "email": "patient@test.com",
    "password": "Pass123!",
    "role": "patient"
  }'

# Login
curl -X POST http://localhost:8000/api/auth/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=patient@test.com&password=Pass123!"

# Response: {"access_token": "eyJ0...", "token_type": "bearer"}
# Use token: -H "Authorization: Bearer YOUR_TOKEN"
```

### Document Analysis Flow
```bash
# Upload document
curl -X POST http://localhost:8000/api/patient/upload/ \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -F "file=@prescription.jpg"

# Trigger analysis
curl -X POST http://localhost:8000/api/documents/1/analyze \
  -H "Authorization: Bearer YOUR_TOKEN"

# Get document with analysis
curl -X GET http://localhost:8000/api/documents/1 \
  -H "Authorization: Bearer YOUR_TOKEN"

# Add clinical note
curl -X POST http://localhost:8000/api/documents/1/notes \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"note": "Patient shows improvement on current medication"}'

# Verify document
curl -X POST http://localhost:8000/api/documents/1/verify \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"notes": "Verified by Dr. Smith"}'
```

---

## Troubleshooting & Common Issues

### Backend Issues

**Port 8000 already in use:**
```bash
# Use different port
uvicorn main:app --reload --port 8001
```

**Database connection error:**
- Ensure PostgreSQL is running
- Check `DATABASE_URL` in `.env`
- Run Prisma migration: `prisma migrate dev`

**Tesseract not found:**
- Install: Ubuntu: `sudo apt-get install tesseract-ocr`
- macOS: `brew install tesseract`
- Windows: Download from GitHub UB-Mannheim/tesseract
- App will work with mock OCR if not installed

**spaCy model not found:**
- Run: `python -m spacy download en_core_web_sm`
- NLP will fallback to regex extraction if not installed

**GPU/CUDA errors:**
- Check: `torch.cuda.is_available()` in Python
- Will fallback to CPU automatically

### Frontend Issues

**Port 5173 already in use:**
```bash
# Vite will auto-select next available port
npm run dev
```

**CORS errors:**
- Ensure backend is running on `http://localhost:8000`
- Check backend `CORS` configuration in `main.py`

**Token expiration:**
- User will be logged out after token expires
- Login again to get new token

### Testing Issues

**Analysis takes too long:**
- First-time model loading: 30-60 seconds (normal)
- Subsequent analyses: 5-10 seconds
- GPU will speed it up significantly

**Mock results instead of real:**
- OCR: Tesseract not installed
- NLP: No medications detected in text
- CV: Model file missing from `backend/models/`

**No documents appearing:**
- Ensure documents were uploaded successfully (check response)
- Refresh the page
- Check browser console for errors

---

## Production Deployment Checklist

- [ ] Set `DEBUG=False` in backend
- [ ] Use strong `SECRET_KEY` in `.env`
- [ ] Configure real database (not local)
- [ ] Set `CORS` origins to production domains
- [ ] Install Tesseract & spaCy model
- [ ] Configure file uploads directory with disk space
- [ ] Set `MAX_CONCURRENT_HEAVY=4-8` for servers
- [ ] Use HTTPS in production
- [ ] Set up proper logging and monitoring
- [ ] Configure backup strategy for database & uploads
