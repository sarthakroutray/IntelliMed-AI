import logging
from typing import List
import asyncio
import os
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi_cache.decorator import cache
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentDetail, DoctorDocumentInfo
from prisma_client import Prisma
from request_cache import (
    doctor_has_patient_access,
    invalidate_doctor_patient_access_cache,
    clear_cache_namespace,
    clear_cache_key,
)
from api.v2.lab_refs import file_ref_name, has_stored_file
import supabase_storage

logger = logging.getLogger(__name__)

router = APIRouter()
CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))


async def _safe_file_url(file_path: str | None) -> str:
    """Best-effort signed URL; '' when there is no file or storage is unhappy."""
    if not has_stored_file(file_path):
        return ''
    try:
        storage_path = supabase_storage.to_storage_path(file_path)
        return await asyncio.to_thread(
            supabase_storage.create_signed_url, str(storage_path)
        )
    except Exception as e:
        logger.warning("  ⚠ Document signed URL unavailable for %s: %s", file_path, e)
        return ''



def _doctor_patients_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    doctor_id = getattr(current_user, "id", "anonymous")
    return f"{namespace}:doctor:{doctor_id}"


def _doctor_patient_documents_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    doctor_id = getattr(current_user, "id", "anonymous")
    patient_id = kwargs.get("patient_id", "unknown")
    return f"{namespace}:doctor:{doctor_id}:patient:{patient_id}"


def _doctor_documents_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    doctor_id = getattr(current_user, "id", "anonymous")
    return f"{namespace}:doctor:{doctor_id}"


@router.get("/patients", response_model=List[User])
@cache(namespace="doctor-patients", expire=CACHE_TTL, key_builder=_doctor_patients_key_builder)
async def get_doctor_patients(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieves a list of all patients assigned to the current doctor.
    """
    if current_user.role not in ('doctor', 'admin'):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can view patients",
        )

    if current_user.role == 'admin':
        patients = await db.user.find_many(where={'role': 'patient'})
        return patients

    patient_links = await db.doctorpatient.find_many(
        where={'doctor_id': current_user.id},
        include={'patient': True}
    )

    unique_patients = []
    seen_patient_ids = set()
    for link in patient_links:
        patient = link.patient
        if not patient or patient.id in seen_patient_ids:
            continue
        seen_patient_ids.add(patient.id)
        unique_patients.append(patient)

    return unique_patients

@router.get("/patients/{patient_id}/documents", response_model=List[DocumentDetail])
@cache(namespace="doctor-patient-docs", expire=CACHE_TTL, key_builder=_doctor_patient_documents_key_builder)
async def get_patient_documents_for_doctor(
    patient_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieves all documents for a specific patient, accessible by a doctor.
    """
    if current_user.role not in ('doctor', 'admin'):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can view patient documents",
        )

    if current_user.role != 'admin':
        has_access = await doctor_has_patient_access(db, current_user.id, patient_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You do not have access to this patient's documents",
            )

    documents = await db.medicaldocument.find_many(
        where={'patient_id': patient_id}
    )

    if current_user.role == 'admin':
        shared_ids = None
    else:
        shares = await db.documentshare.find_many(
            where={'doctor_id': current_user.id}
        )
        shared_ids = {s.document_id for s in shares}
        documents = [d for d in documents if d.id in shared_ids]
    
    result = []
    for doc in documents:
        filename = file_ref_name(doc.file_path)
        file_url = await _safe_file_url(doc.file_path)

        result.append(
            DocumentDetail(
                id=doc.id,
                filename=filename,
                file_url=file_url,
                upload_timestamp=doc.upload_timestamp,
                ai_analysis=doc.ai_analysis_json,
                analysis_status="processed" if doc.ai_analysis_json else "pending",
            )
        )

    return result


@router.get("/documents", response_model=List[DoctorDocumentInfo])
@cache(namespace="doctor-documents", expire=CACHE_TTL, key_builder=_doctor_documents_key_builder)
async def get_all_doctor_documents(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieves all documents shared with the current doctor across all linked patients.
    """
    if current_user.role not in ('doctor', 'admin'):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can view shared documents",
        )

    if current_user.role == 'admin':
        documents = await db.medicaldocument.find_many(
            include={'users': True},
            order={'upload_timestamp': 'desc'},
        )
    else:
        shares = await db.documentshare.find_many(
            where={'doctor_id': current_user.id},
            include={'document': {'include': {'users': True}}},
            order={'shared_at': 'desc'},
        )
        documents = [s.document for s in shares if s.document is not None]

    result = []
    for doc in documents:
        patient = doc.users
        filename = file_ref_name(doc.file_path)
        file_url = await _safe_file_url(doc.file_path)

        result.append(
            DoctorDocumentInfo(
                id=doc.id,
                filename=filename,
                file_url=file_url,
                upload_timestamp=doc.upload_timestamp,
                ai_analysis=doc.ai_analysis_json,
                analysis_status="processed" if doc.ai_analysis_json else "pending",
                patient_id=doc.patient_id or 0,
                patient_email=patient.email if patient else "Unknown",
                patient_name=patient.name if (patient and patient.name) else None,
                verified_at=doc.verified_at,
                verified_by=doc.verified_by,
                archived=doc.archived,
            )
        )

    return result


@router.delete("/patients/{patient_id}")
async def unlink_patient(
    patient_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Unlink a patient from the current doctor and remove shared document access.
    """
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can unlink patients",
        )

    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': patient_id,
        }
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Patient link not found",
        )

    # Delete the link
    await db.doctorpatient.delete(where={'id': link.id})

    # Delete any document shares between this doctor and this patient's documents
    patient_docs = await db.medicaldocument.find_many(
        where={'patient_id': patient_id}
    )
    doc_ids = [d.id for d in patient_docs]
    if doc_ids:
        await db.documentshare.delete_many(
            where={
                'doctor_id': current_user.id,
                'document_id': {'in': doc_ids},
            }
        )

    # Invalidate caches
    invalidate_doctor_patient_access_cache(doctor_id=current_user.id, patient_id=patient_id)
    try:
        await clear_cache_namespace("doctor-patients")
        await clear_cache_key("doctor-patients", f"doctor:{current_user.id}")
        await clear_cache_namespace("doctor-documents")
        await clear_cache_key("doctor-documents", f"doctor:{current_user.id}")
        await clear_cache_namespace("doctor-patient-docs")
        await clear_cache_key("doctor-patient-docs", f"doctor:{current_user.id}:patient:{patient_id}")
        await clear_cache_namespace("linked-doctors")
        await clear_cache_key("linked-doctors", f"user:{patient_id}")
    except Exception:
        pass

    logger.info("✓ Doctor %s unlinked patient %s", current_user.id, patient_id)
    return {"message": "Patient unlinked successfully"}


