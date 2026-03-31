import os
from pathlib import Path
from dotenv import load_dotenv

env_path = Path(__file__).parent / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent.parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi_cache import FastAPICache
from fastapi_cache.backends.inmemory import InMemoryBackend
from api import auth_router, patient_router, doctor_router, linking_router, document_router, profile_router, sharing_router
from prisma_db import db

google_client_id = os.getenv('GOOGLE_CLIENT_ID')
if google_client_id:
    print(f"✓ GOOGLE_CLIENT_ID loaded: {google_client_id[:20]}...")
else:
    print("⚠ GOOGLE_CLIENT_ID not found in environment")


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    print("✓ Database connected")
    FastAPICache.init(InMemoryBackend(), prefix="intellimed-cache")
    print("✓ In-memory cache initialised")
    yield
    if db.is_connected():
        await db.disconnect()
        print("✓ Database disconnected")


app = FastAPI(title="IntelliMed AI", lifespan=lifespan)

origins = [o.strip() for o in os.getenv("CORS_ORIGINS", "").split(",") if o.strip()]
origin_regex = os.getenv("CORS_ORIGIN_REGEX") or None

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_origin_regex=origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)

# Mount uploads directory for serving files
uploads_dir = Path(__file__).parent / "uploads"
uploads_dir.mkdir(exist_ok=True)
app.mount("/uploads", StaticFiles(directory=str(uploads_dir)), name="uploads")

app.include_router(auth_router.router, prefix="/api/auth", tags=["auth"])
app.include_router(patient_router.router, prefix="/api/patient", tags=["patient"])
app.include_router(doctor_router.router, prefix="/api/doctor", tags=["doctor"])
app.include_router(linking_router.router, prefix="/api", tags=["linking"])
app.include_router(document_router.router, prefix="/api", tags=["documents"])
app.include_router(profile_router.router, prefix="/api", tags=["profile"])
app.include_router(sharing_router.router, prefix="/api/patient", tags=["sharing"])

@app.get("/")
def read_root():
    return {"message": "Welcome to IntelliMed AI"}
