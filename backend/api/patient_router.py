from typing import List
import shutil
import asyncio
import json
from pathlib import Path
from fastapi import APIRouter, Depends, UploadFile, File, HTTPException, status

import sys
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentInfo, DocumentDetail
from prisma_client import Prisma
from prisma_client.fields import Json
import services

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

    try:
        file_path = UPLOAD_DIR / file.filename
        with file_path.open("wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        ocr_task = asyncio.create_task(services.ocr_service(str(file_path)))
        cv_task = asyncio.create_task(services.cv_service(str(file_path)))

        ocr_result = await ocr_task
        nlp_task = asyncio.create_task(services.nlp_service(ocr_result))

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
                'ai_analysis_json': Json(aggregated_analysis),
            }
        )

        print(f"✓ Document uploaded successfully: {db_document.id}")
        return DocumentInfo(
            id=db_document.id,
            filename=file.filename,
            upload_timestamp=db_document.upload_timestamp,
            ai_analysis=db_document.ai_analysis_json,
        )
    except Exception as e:
        print(f"✗ Document upload failed: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Document upload failed: {str(e)}"
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

    try:
        documents = await db.medicaldocument.find_many(
            where={'patient_id': current_user.id}
        )
        print(f"✓ Found {len(documents)} documents for user {current_user.id}")
        return [
            DocumentInfo(
                id=doc.id,
                filename=doc.file_path.split('/')[-1],
                upload_timestamp=doc.upload_timestamp,
                ai_analysis=doc.ai_analysis_json,
            )
            for doc in documents
        ]
    except Exception as e:
        print(f"✗ Failed to fetch documents: {str(e)}")
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
        file_path = Path(document.file_path)
        if file_path.exists():
            file_path.unlink()
    except Exception as e:
        print(f"Error deleting file: {e}")

    await db.medicaldocument.delete(
        where={'id': document_id}
    )

    return None


@router.get("/linked-doctors", response_model=List[User])
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
        }
    )
    doctor_ids = [link.doctor_id for link in doctor_links if link.doctor_id]

    doctors = await db.user.find_many(
        where={'id': {'in': doctor_ids}}
    )
    return doctors

