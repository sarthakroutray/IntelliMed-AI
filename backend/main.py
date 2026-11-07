import asyncio
import logging
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
from api.v2 import lab_report_router
from prisma_db import db
import services

logger = logging.getLogger(__name__)

google_client_id = os.getenv('GOOGLE_CLIENT_ID')
if google_client_id:
    logger.info("✓ GOOGLE_CLIENT_ID loaded: %s...", google_client_id[:20])
else:
    logger.warning("⚠ GOOGLE_CLIENT_ID not found in environment")

AI_WARMUP_ON_STARTUP = os.getenv("AI_WARMUP_ON_STARTUP", "true").strip().lower() in ("1", "true", "yes")
AI_WARMUP_DELAY_SECONDS = float(os.getenv("AI_WARMUP_DELAY_SECONDS", "15"))


async def _warmup_models_in_background():
    """Pay the AI model load cost up front so the first upload doesn't spend
    minutes downloading/loading models inside a single request.

    An initial delay gives early startup requests (health checks, login, initial
    dashboard queries) full CPU and event-loop availability before background
    model warmup begins."""
    try:
        if AI_WARMUP_DELAY_SECONDS > 0:
            await asyncio.sleep(AI_WARMUP_DELAY_SECONDS)
        await asyncio.to_thread(services.warmup_models)
        logger.info("✓ AI models warmed up")
    except asyncio.CancelledError:
        pass
    except Exception as e:
        logger.warning("⚠ AI model warm-up failed (models will load on first request): %s", e)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await db.connect()
    logger.info("✓ Database connected")
    FastAPICache.init(InMemoryBackend(), prefix="intellimed-cache")
    logger.info("✓ In-memory cache initialised")
    warmup_task = None
    if AI_WARMUP_ON_STARTUP:
        warmup_task = asyncio.create_task(_warmup_models_in_background())
    yield
    if warmup_task is not None and not warmup_task.done():
        warmup_task.cancel()
    if db.is_connected():
        await db.disconnect()
        logger.info("✓ Database disconnected")


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

# API v1 — existing website contract. Do not change routes/handlers without
# updating the frontend; paths are frozen for backwards compatibility.
app.include_router(auth_router.router, prefix="/api/v1/auth", tags=["auth"])
app.include_router(patient_router.router, prefix="/api/v1/patient", tags=["patient"])
app.include_router(doctor_router.router, prefix="/api/v1/doctor", tags=["doctor"])
app.include_router(linking_router.router, prefix="/api/v1", tags=["linking"])
app.include_router(document_router.router, prefix="/api/v1", tags=["documents"])
app.include_router(profile_router.router, prefix="/api/v1", tags=["profile"])
app.include_router(sharing_router.router, prefix="/api/v1/patient", tags=["sharing"])

# API v2 — new functionality (lab report understanding, future app clients).
app.include_router(lab_report_router.router, prefix="/api/v2", tags=["v2-lab-reports"])

@app.get("/")
def read_root():
    return {"message": "Welcome to IntelliMed AI"}
