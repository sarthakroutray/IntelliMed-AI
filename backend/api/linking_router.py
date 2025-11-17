import secrets
from fastapi import APIRouter, Depends, HTTPException, status
from backend.auth import get_current_user
from backend.prisma_db import get_db
from backend.schemas import User
from backend.prisma_client import Prisma

router = APIRouter(
    tags=["linking"],
)

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
async def link_patient(access_code: str, current_user: User = Depends(get_current_user), db: Prisma = Depends(get_db)):
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can link with patients",
        )

    link_request = await db.doctorpatient.find_unique(where={'access_code': access_code})

    if not link_request or link_request.doctor_id is not None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Invalid or already used access code",
        )

    await db.doctorpatient.update(
        where={'access_code': access_code},
        data={'doctor_id': current_user.id}
    )

    return {"message": "Patient linked successfully"}
