import secrets
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from fastapi_cache import FastAPICache

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User
from prisma_client import Prisma
from request_cache import invalidate_doctor_patient_access_cache, clear_cache_namespace, clear_cache_key

router = APIRouter(
    tags=["linking"],
)


class LinkPatientRequest(BaseModel):
    access_code: str


async def _invalidate_link_related_caches(patient_id: int, doctor_id: int) -> None:
    invalidate_doctor_patient_access_cache(doctor_id=doctor_id, patient_id=patient_id)
    try:
        await clear_cache_namespace("linked-doctors")
        await clear_cache_key("linked-doctors", f"user:{patient_id}")
        await clear_cache_namespace("doctor-patients")
        await clear_cache_namespace("doctor-patient-docs")
    except Exception:
        pass


@router.post("/patient/generate-access-code", status_code=status.HTTP_201_CREATED)
async def generate_access_code(current_user: User = Depends(get_current_user), db: Prisma = Depends(get_db)):
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can generate access codes",
        )

    access_code = secrets.token_hex(3).upper()

    await db.doctorpatient.create(
        data={
            'patient_id': current_user.id,
            'access_code': access_code,
        }
    )

    return {"access_code": access_code}

@router.post("/doctor/link-patient", status_code=status.HTTP_200_OK)
async def link_patient(request: LinkPatientRequest, current_user: User = Depends(get_current_user), db: Prisma = Depends(get_db)):
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can link with patients",
        )

    code = request.access_code.strip().upper()
    link_request = await db.doctorpatient.find_unique(where={'access_code': code})

    if not link_request or link_request.doctor_id is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or already used access code",
        )

    if link_request.patient_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot link doctor to themselves",
        )

    existing_link = await db.doctorpatient.find_first(
        where={'doctor_id': current_user.id, 'patient_id': link_request.patient_id}
    )
    if existing_link:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Doctor is already linked to this patient",
        )

    # Atomic conditional update prevents race condition where two doctors claim the same code
    updated_count = await db.doctorpatient.update_many(
        where={'access_code': code, 'doctor_id': None},
        data={'doctor_id': current_user.id}
    )
    if updated_count == 0:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or already used access code",
        )

    await _invalidate_link_related_caches(
        patient_id=link_request.patient_id,
        doctor_id=current_user.id,
    )

    return {"message": "Patient linked successfully"}
