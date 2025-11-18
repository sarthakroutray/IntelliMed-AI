from typing import List
import shutil
import asyncio
import json
from pathlib import Path
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status
from backend.auth import get_current_user
from backend.prisma_db import get_db
from backend.schemas import User, DocumentInfo, DocumentDetail
from backend.prisma_client import Prisma
from backend import services

router = APIRouter()

UPLOAD_DIR = Path("./uploads")
UPLOAD_DIR.mkdir(exist_ok=True)


@router.post("/upload/", response_model=DocumentInfo)
async def upload_document(
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

    db_document = await db.medicaldocument.create(
        data={
            'patient_id': current_user.id,
            'file_path': str(file_path),
            'ai_analysis_json': json.dumps(aggregated_analysis),
        }
    )

    return DocumentInfo(
        id=db_document.id,
        filename=file.filename,
        upload_timestamp=db_document.upload_timestamp,
        ai_analysis=db_document.ai_analysis_json,
    )

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

    documents = await db.medicaldocument.find_many(
        where={'patient_id': current_user.id}
    )
    return [
        DocumentInfo(
            id=doc.id,
            filename=doc.file_path.split('/')[-1],
            upload_timestamp=doc.upload_timestamp,
            ai_analysis=doc.ai_analysis_json,
        )
        for doc in documents
    ]


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

    # Find the document
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

    # Delete file from filesystem
    try:
        file_path = Path(document.file_path)
        if file_path.exists():
            file_path.unlink()
    except Exception as e:
        print(f"Error deleting file: {e}")

    # Delete from DB
    await db.medicaldocument.delete(
        where={'id': document_id}
    )

    return None

