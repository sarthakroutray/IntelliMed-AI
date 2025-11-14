from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from backend import models, schemas, auth
from backend.database import get_db

router = APIRouter()


@router.get("/patients/", response_model=List[schemas.UserInDB])
def get_patients(
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.require_role("doctor")),
):
    patients = db.query(models.User).filter(models.User.role == "patient").all()
    return patients


@router.get(
    "/patients/{patient_id}/documents", response_model=List[schemas.DocumentInfo]
)
def get_patient_documents(
    patient_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.require_role("doctor")),
):
    patient = db.query(models.User).filter(models.User.id == patient_id).first()
    if not patient or patient.role != "patient":
        raise HTTPException(status_code=404, detail="Patient not found")

    documents = (
        db.query(models.MedicalDocument)
        .filter(models.MedicalDocument.patient_id == patient_id)
        .all()
    )
    
    return [
        schemas.DocumentInfo(
            filename=doc.file_path.split('/')[-1],
            upload_timestamp=doc.upload_timestamp,
            ai_analysis=doc.ai_analysis_json,
        )
        for doc in documents
    ]
