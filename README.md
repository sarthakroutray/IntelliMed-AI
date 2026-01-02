    # IntelliMed-AI

IntelliMed-AI is a comprehensive medical application designed to bridge the gap between patients and doctors. It facilitates secure medical document management, patient-doctor linking, and leverages AI for analyzing medical records.

## Features

- **Role-Based Access Control**: Distinct dashboards for Patients, Doctors, and Admins.
- **Authentication**: Secure login and registration with email/password and Google OAuth support.
- **Patient Dashboard**:
  - Securely upload and store medical documents.
  - View AI-generated analysis of medical records.
  - Manage access permissions for doctors.
- **Doctor Dashboard**:
  - View linked patients.
  - Access patient medical documents and history.
- **Patient-Doctor Linking**: Secure linking mechanism using unique access codes.

## Tech Stack

### Backend
- **Framework**: [FastAPI](https://fastapi.tiangolo.com/) (Python)
- **Database ORM**: [Prisma](https://prisma.io/) (with `prisma-client-py`)
- **Database**: PostgreSQL
- **Authentication**: JWT (JSON Web Tokens) & Google OAuth
- **File Handling**: `python-multipart` for uploads

### Frontend
- **Framework**: [React](https://reactjs.org/) with [Vite](https://vitejs.dev/)
- **Styling**: [Tailwind CSS](https://tailwindcss.com/)
- **Routing**: React Router
- **HTTP Client**: Axios

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

4. Set up environment variables:
   - Create a `.env` file in the `backend` directory.
   - Add necessary variables (DATABASE_URL, DIRECT_URL, SECRET_KEY, GOOGLE_CLIENT_ID, etc.).

5. Generate Prisma client:
   ```bash
   prisma generate
   ```

6. Run the server:
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
