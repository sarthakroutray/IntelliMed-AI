import shutil
import asyncio
from pathlib import Path
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from sqlalchemy.orm import Session

from backend import models, schemas, auth, services
from backend.database import get_db

router = APIRouter()

UPLOAD_DIR = Path("./uploads")
UPLOAD_DIR.mkdir(exist_ok=True)


@router.post("/upload/", response_model=schemas.DocumentInfo)
async def upload_document(
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(auth.require_role("patient")),
):
    if not file.filename:
        raise HTTPException(status_code=400, detail="No file provided")

    file_path = UPLOAD_DIR / file.filename
    with file_path.open("wb") as buffer:
        shutil.copyfileobj(file.file, buffer)

    # Run AI services concurrently
    ocr_task = asyncio.create_task(services.mock_ocr_service(str(file_path)))
    cv_task = asyncio.create_task(services.mock_cv_service(str(file_path)))

    ocr_result = await ocr_task
    nlp_task = asyncio.create_task(services.mock_nlp_service(ocr_result))

    cv_result = await cv_task
    nlp_result = await nlp_task

    aggregated_analysis = {
        "ocr_result": ocr_result,
        "nlp_result": nlp_result,
        "cv_result": cv_result,
    }

    db_document = models.MedicalDocument(
        patient_id=current_user.id,
        file_path=str(file_path),
        ai_analysis_json=aggregated_analysis,
    )
    db.add(db_document)
    db.commit()
    db.refresh(db_document)

    return schemas.DocumentInfo(
        filename=file.filename,
        upload_timestamp=db_document.upload_timestamp,
        ai_analysis=db_document.ai_analysis_json,
    )
