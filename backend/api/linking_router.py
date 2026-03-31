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
from request_cache import invalidate_doctor_patient_access_cache

router = APIRouter(
    tags=["linking"],
)


class LinkPatientRequest(BaseModel):
    access_code: str


async def _invalidate_link_related_caches(patient_id: int, doctor_id: int) -> None:
    invalidate_doctor_patient_access_cache(doctor_id=doctor_id, patient_id=patient_id)
    try:
        backend = FastAPICache.get_backend()
        await backend.clear(namespace=None, key=f"linked-doctors:user:{patient_id}")
        await backend.clear(namespace="doctor-patients")
        await backend.clear(namespace="doctor-patient-docs")
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

    link_request = await db.doctorpatient.find_unique(where={'access_code': request.access_code})

    if not link_request or link_request.doctor_id is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or already used access code",
        )

    await db.doctorpatient.update(
        where={'access_code': request.access_code},
        data={'doctor_id': current_user.id}
    )

    await _invalidate_link_related_caches(
        patient_id=link_request.patient_id,
        doctor_id=current_user.id,
    )

    return {"message": "Patient linked successfully"}
