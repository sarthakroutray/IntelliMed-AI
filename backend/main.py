import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables FIRST, before any other imports
env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

# Now import FastAPI and other modules that depend on environment variables
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from backend.api import auth_router, patient_router, doctor_router

# Debug: Check if GOOGLE_CLIENT_ID is loaded
google_client_id = os.getenv('GOOGLE_CLIENT_ID')
if google_client_id:
    print(f"✓ GOOGLE_CLIENT_ID loaded: {google_client_id[:20]}...")
else:
    print("⚠ GOOGLE_CLIENT_ID not found in environment")

app = FastAPI(title="IntelliMed AI")

# CORS configuration
origins = [
    "http://localhost",
    "http://localhost:3000",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router.router, prefix="/api", tags=["auth"])
app.include_router(patient_router.router, prefix="/api", tags=["patient"])
app.include_router(doctor_router.router, prefix="/api", tags=["doctor"])

@app.get("/")
def read_root():
    return {"message": "Welcome to IntelliMed AI"}
