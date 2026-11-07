import logging
from typing import List
import os
import tempfile
import asyncio
from pathlib import Path
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status, Request, BackgroundTasks

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentInfo
from prisma_client import Prisma
from prisma_client.fields import Json
from request_cache import clear_cache_namespace
from api.v2.lab_refs import file_ref_name
import services
import supabase_storage

from fastapi_cache import FastAPICache
from fastapi_cache.decorator import cache

logger = logging.getLogger(__name__)

router = APIRouter()

MAX_UPLOAD_SIZE_MB = int(os.getenv("MAX_UPLOAD_SIZE_MB", "10"))
CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))

# Upper bound for the inline AI pipeline (OCR/CV/NLP/summarize) during upload.
# Model downloads + CPU inference on a cold host can take minutes; the client
# waits up to 15 min (HEAVY_TIMEOUT_MS), so this must stay well below that.
# On timeout the document is still persisted with pending analysis instead of
# hanging the request until the client gives up.
AI_PIPELINE_TIMEOUT_S = int(os.getenv("AI_PIPELINE_TIMEOUT_S", "480"))


def _patient_documents_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    user_id = getattr(current_user, "id", "anonymous")
    return f"{namespace}:user:{user_id}"


def _linked_doctors_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    user_id = getattr(current_user, "id", "anonymous")
    return f"{namespace}:user:{user_id}"


async def _invalidate_patient_related_caches(patient_id: int) -> None:
    try:
        # Clear full namespaces accounting for FastAPICache prefix
        await clear_cache_namespace("patient-docs")
        await clear_cache_namespace("linked-doctors")
        # Doctor caches can include this patient's documents.
        await clear_cache_namespace("doctor-patient-docs")
    except Exception:
        pass


async def _analyze_upload_in_background(
    document_id: int,
    storage_path: str,
    patient_id: int,
) -> None:
    """Run OCR/CV/NLP/summarize after the upload response was sent.

    Keeps the upload endpoint fast (the 99% hang was the client waiting on
    inline model downloads + CPU inference). Failures leave the document in
    pending state so the UI Analyze button can retry.
    """
    from prisma_db import db as _db

    tmp_path: str | None = None
    try:
        if not _db.is_connected():
            await _db.connect()
    except Exception:
        pass
    try:
        try:
            tmp_path = await asyncio.to_thread(
                supabase_storage.download_to_temp, storage_path
            )
        except Exception as e:
            logger.warning("Background analysis: download failed for doc %s: %s", document_id, e)
            return

        async def _run_ai_pipeline() -> dict:
            ocr_task = asyncio.create_task(services.ocr_service(tmp_path))
            cv_task = asyncio.create_task(services.cv_service(tmp_path))
            ocr_result = await ocr_task
            nlp_task = asyncio.create_task(services.nlp_service(ocr_result))
            cv_result = await cv_task
            nlp_result = await nlp_task
            summary_result = await services.medical_summarize_service(ocr_result, nlp_result)
            return {
                "ocr_result": ocr_result,
                "nlp_result": nlp_result,
                "cv_result": cv_result,
                "summary_result": summary_result,
            }

        try:
            pipeline = await asyncio.wait_for(
                _run_ai_pipeline(), timeout=AI_PIPELINE_TIMEOUT_S
            )
        except asyncio.TimeoutError:
            logger.warning(
                "Background AI pipeline timed out after %ss for doc %s; leaving pending",
                AI_PIPELINE_TIMEOUT_S, document_id,
            )
            return

        ocr_result = pipeline["ocr_result"]
        nlp_result = pipeline["nlp_result"]
        cv_result = pipeline["cv_result"]
        summary_result = pipeline["summary_result"]

        is_prescription = nlp_result.get('is_prescription', False)
        has_medications = len(nlp_result.get('medications', [])) > 0
        is_meaningful_xray = (
            not is_prescription and
            not has_medications and
            cv_result.get('classification') and
            cv_result.get('confidence', 0) > 0.6 and
            cv_result.get('document_type') == 'xray'
        )
        if not is_meaningful_xray and cv_result.get('document_type') == 'xray':
            cv_result['document_type'] = 'document'
        if is_prescription or has_medications:
            final_type = "prescription"
        elif is_meaningful_xray:
            final_type = "xray"
        else:
            final_type = "document"

        aggregated_analysis = {
            "ocr_result": ocr_result,
            "nlp_result": nlp_result,
            "cv_result": cv_result,
            "summary_result": summary_result,
            "detected_type": final_type,
            "analysis_pending": False,
        }
        try:
            await _db.medicaldocument.update(
                where={'id': document_id},
                data={'ai_analysis_json': Json(aggregated_analysis)},
            )
            logger.info("✓ Background analysis completed for doc %s", document_id)
        except Exception as e:
            logger.warning("Background analysis: DB update failed for doc %s: %s", document_id, e)
    except Exception as e:
        logger.warning("Background analysis failed for doc %s: %s", document_id, e)
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        try:
            await _invalidate_patient_related_caches(patient_id)
        except Exception:
            pass


@router.post("/upload/", response_model=DocumentInfo)
async def upload_document(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can upload documents",
        )

    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")

    tmp_path: str | None = None
    try:
        # Read file content
        file_bytes = await file.read()

        # Enforce upload size limit
        max_bytes = MAX_UPLOAD_SIZE_MB * 1024 * 1024
        if len(file_bytes) > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"File too large. Maximum allowed size is {MAX_UPLOAD_SIZE_MB} MB.",
            )

        # Upload to Supabase Storage (blocking client — keep it off the loop).
        # No temp file is written on the request path: the response returns as
        # soon as the bytes are stored, and AI analysis runs afterwards in the
        # background (or via the UI Analyze button).
        storage_path = f"patients/{current_user.id}/{file.filename}"
        stored_path = await asyncio.to_thread(
            supabase_storage.upload_file,
            file_bytes=file_bytes,
            destination_path=storage_path,
            content_type=file.content_type,
        )

        db_document = await db.medicaldocument.create(
            data={
                'patient_id': current_user.id,
                'file_path': stored_path,
                'ai_analysis_json': Json(None),
            }
        )

        # Schedule analysis without blocking the response. BackgroundTasks runs
        # after the response is sent; fall back to a fire-and-forget task if
        # scheduling fails so the upload still succeeds.
        try:
            background_tasks.add_task(
                _analyze_upload_in_background,
                db_document.id, stored_path, current_user.id,
            )
        except Exception as e:
            logger.warning("Could not schedule background analysis: %s", e)
            try:
                asyncio.create_task(
                    _analyze_upload_in_background(
                        db_document.id, stored_path, current_user.id
                    )
                )
            except Exception:
                pass

        logger.info("✓ Document uploaded successfully: %s", db_document.id)
        return DocumentInfo(
            id=db_document.id,
            filename=file.filename,
            upload_timestamp=db_document.upload_timestamp,
            ai_analysis=None,
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("✗ Document upload failed: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Document upload failed: {str(e)}"
        )
    finally:
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        await _invalidate_patient_related_caches(current_user.id)

@router.get("/documents", response_model=List[DocumentInfo])
async def get_own_documents(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can view their documents",
        )

    try:
        documents = await db.medicaldocument.find_many(
            where={'patient_id': current_user.id}
        )
        logger.info("✓ Found %s documents for user %s", len(documents), current_user.id)
        return [
            DocumentInfo(
                id=doc.id,
                filename=file_ref_name(doc.file_path),
                upload_timestamp=doc.upload_timestamp,
                ai_analysis=doc.ai_analysis_json,
            )
            for doc in documents
        ]
    except Exception as e:
        logger.error("✗ Failed to fetch documents: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch documents: {str(e)}"
        )


@router.delete("/documents/{document_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_document(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can delete documents",
        )

    document = await db.medicaldocument.find_first(
        where={
            'id': document_id,
            'patient_id': current_user.id
        }
    )

    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )

    try:
        # Delete from Supabase Storage if a file URL is stored
        if document.file_path:
            try:
                storage_path = supabase_storage.to_storage_path(document.file_path)
                await asyncio.to_thread(supabase_storage.delete_file, storage_path)
            except Exception as e:
                logger.warning("Warning: could not delete file from storage: %s", e)

        await db.medicaldocument.delete(
            where={'id': document_id}
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.error("✗ Failed to delete document: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete document: {str(e)}",
        )
    finally:
        await _invalidate_patient_related_caches(current_user.id)

    return None


@router.get("/linked-doctors", response_model=List[User])
@cache(namespace="linked-doctors", expire=CACHE_TTL, key_builder=_linked_doctors_key_builder)
async def get_linked_doctors(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieves a list of all doctors that have been granted access to the patient's records.
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can view their linked doctors",
        )

    doctor_links = await db.doctorpatient.find_many(
        where={
            'patient_id': current_user.id,
            'doctor_id': {'not': None}
        },
        include={'doctor': True}
    )

    unique_doctors = []
    seen_doctor_ids = set()
    for link in doctor_links:
        doctor = link.doctor
        if not doctor or doctor.id in seen_doctor_ids:
            continue
        seen_doctor_ids.add(doctor.id)
        unique_doctors.append(doctor)

    return unique_doctors

