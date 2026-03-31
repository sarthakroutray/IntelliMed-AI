from typing import List
import os
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi_cache.decorator import cache
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentDetail
from prisma_client import Prisma
from request_cache import doctor_has_patient_access

router = APIRouter()
CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))


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

@router.get("/patients", response_model=List[User])
@cache(namespace="doctor-patients", expire=CACHE_TTL, key_builder=_doctor_patients_key_builder)
async def get_doctor_patients(
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieves a list of all patients assigned to the current doctor.
    """
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can view patients",
        )

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
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can view patient documents",
        )

    has_access = await doctor_has_patient_access(db, current_user.id, patient_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You do not have access to this patient's documents",
        )

    documents = await db.medicaldocument.find_many(
        where={'patient_id': patient_id}
    )
    
    return [
        DocumentDetail(
            id=doc.id,
            filename=Path(doc.file_path.split("?")[0]).name if doc.file_path else "N/A",
            file_url=doc.file_path or "",
            upload_timestamp=doc.upload_timestamp,
            ai_analysis=doc.ai_analysis_json,
            analysis_status="processed" if doc.ai_analysis_json else "pending",
        )
        for doc in documents
    ]

