import os
from pathlib import Path
from dotenv import load_dotenv

env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from backend.api import auth_router, patient_router, doctor_router, linking_router
from backend.prisma_db import db

google_client_id = os.getenv('GOOGLE_CLIENT_ID')
if google_client_id:
    print(f"✓ GOOGLE_CLIENT_ID loaded: {google_client_id[:20]}...")
else:
    print("⚠ GOOGLE_CLIENT_ID not found in environment")

app = FastAPI(title="IntelliMed AI")

@app.on_event("startup")
async def startup():
    await db.connect()
    print("✓ Database connected")

@app.on_event("shutdown")
async def shutdown():
    if db.is_connected():
        await db.disconnect()
        print("✓ Database disconnected")

origins = [
    "http://localhost",
    "http://localhost:3000",
    "http://localhost:3001",
    "http://127.0.0.1:3000",
    "http://127.0.0.1:3001",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
app.include_router(patient_router.router, prefix="/api/patient", tags=["patient"])
app.include_router(doctor_router.router, prefix="/api/doctor", tags=["doctor"])
app.include_router(linking_router.router, prefix="/api", tags=["linking"])

@app.get("/")
def read_root():
    return {"message": "Welcome to IntelliMed AI"}
