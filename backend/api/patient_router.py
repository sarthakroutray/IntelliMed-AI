from typing import List
import os
import tempfile
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
import supabase_storage

from fastapi_cache import FastAPICache

router = APIRouter()

MAX_UPLOAD_SIZE_MB = int(os.getenv("MAX_UPLOAD_SIZE_MB", "10"))


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
        # Read file content
        file_bytes = await file.read()

        # Enforce upload size limit
        max_bytes = MAX_UPLOAD_SIZE_MB * 1024 * 1024
        if len(file_bytes) > max_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=f"File too large. Maximum allowed size is {MAX_UPLOAD_SIZE_MB} MB.",
            )

        # Write to a temp file so AI services can read it from disk
        suffix = Path(file.filename).suffix or ".bin"
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(file_bytes)
            tmp_path = tmp.name

        # Upload to Supabase Storage
        storage_path = f"patients/{current_user.id}/{file.filename}"
        public_url = supabase_storage.upload_file(
            file_bytes=file_bytes,
            destination_path=storage_path,
            content_type=file.content_type,
        )

        ocr_task = asyncio.create_task(services.ocr_service(tmp_path))
        cv_task = asyncio.create_task(services.cv_service(tmp_path))

        ocr_result = await ocr_task
        nlp_task = asyncio.create_task(services.nlp_service(ocr_result))

        cv_result = await cv_task
        nlp_result = await nlp_task

        # Run T5 medical summarization on OCR text + NLP context
        summary_result = await services.medical_summarize_service(ocr_result, nlp_result)

        # Determine final document type based on content quality
        # Priority: NLP prescription detection > CV X-ray classification > default
        is_prescription = nlp_result.get('is_prescription', False)
        has_medications = len(nlp_result.get('medications', [])) > 0
        
        print(f"  Document type detection: is_prescription={is_prescription}, has_medications={has_medications}, medications={nlp_result.get('medications', [])}")
        
        # Only consider it an X-ray if NO prescription markers are found
        is_meaningful_xray = (
            not is_prescription and
            not has_medications and
            cv_result.get('classification') and 
            cv_result.get('confidence', 0) > 0.6 and  # Higher threshold to reduce false positives
            cv_result.get('document_type') == 'xray'
        )
        
        # Override document types if not meaningful
        if not is_meaningful_xray and cv_result.get('document_type') == 'xray':
            cv_result['document_type'] = 'document'  # Demote random images
        
        # Determine final type: prescription has highest priority
        if is_prescription or has_medications:
            final_type = "prescription"
        elif is_meaningful_xray:
            final_type = "xray"
        else:
            final_type = "document"
        
        print(f"  Final document type: {final_type}")

        aggregated_analysis = {
            "ocr_result": ocr_result,
            "nlp_result": nlp_result,
            "cv_result": cv_result,
            "summary_result": summary_result,
            "detected_type": final_type,
        }

        db_document = await db.medicaldocument.create(
            data={
                'patient_id': current_user.id,
                'file_path': public_url,
                'ai_analysis_json': Json(aggregated_analysis),
            }
        )

        # Clean up temp file
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

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
    finally:
        # Invalidate the cached document list for this patient (non-fatal)
        try:
            cache_key = f"patient-docs:user:{current_user.id}"
            await FastAPICache.get_backend().clear(namespace=None, key=cache_key)
        except Exception:
            pass

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
                filename=Path(doc.file_path.split("?")[0]).name if doc.file_path else "unknown",
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
        # Delete from Supabase Storage if a file URL is stored
        if document.file_path:
            try:
                storage_path = supabase_storage.public_url_to_storage_path(document.file_path)
                supabase_storage.delete_file(storage_path)
            except Exception as e:
                print(f"Warning: could not delete file from storage: {e}")

        await db.medicaldocument.delete(
            where={'id': document_id}
        )
    except Exception as e:
        print(f"✗ Failed to delete document: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete document: {str(e)}",
        )
    finally:
        # Invalidate cached document list for this patient (non-fatal)
        try:
            cache_key = f"patient-docs:user:{current_user.id}"
            await FastAPICache.get_backend().clear(namespace=None, key=cache_key)
        except Exception:
            pass

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

