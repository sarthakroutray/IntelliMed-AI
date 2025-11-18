from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from backend.auth import get_current_user
from backend.prisma_db import get_db
from backend.schemas import User, DocumentDetail
from backend.prisma_client import Prisma

router = APIRouter()

@router.get("/patients", response_model=List[User])
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
        where={'doctor_id': current_user.id}
    )
    patient_ids = [link.patient_id for link in patient_links]

    patients = await db.user.find_many(
        where={'id': {'in': patient_ids}}
    )
    return patients

@router.get("/patients/{patient_id}/documents", response_model=List[DocumentDetail])
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

    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': patient_id,
        }
    )

    if not link:
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
            filename=doc.file_path.split('/')[-1] if doc.file_path else "N/A",
            file_url=f"/uploads/{doc.file_path.split('/')[-1]}" if doc.file_path else "",
            upload_timestamp=doc.upload_timestamp,
            ai_analysis=doc.ai_analysis_json,
            analysis_status="processed" if doc.ai_analysis_json else "pending",
        )
        for doc in documents
    ]

