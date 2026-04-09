from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Request, Body, Query
from fastapi.responses import RedirectResponse
from fastapi_cache import FastAPICache
from fastapi_cache.decorator import cache
from datetime import datetime
from pydantic import BaseModel
import sys
import os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import asyncio
from auth import get_current_user
from prisma_db import get_db
from schemas import User
from prisma_client import Prisma, Json
from request_cache import doctor_has_patient_access
import services
import supabase_storage

router = APIRouter()

CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))


class VerifyDocumentRequest(BaseModel):
    notes: Optional[str] = None


class ClinicalNoteRequest(BaseModel):
    note: str


def _doc_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    """Stable, user-scoped per-document cache key."""
    doc_id = kwargs.get("document_id", "?")
    current_user = kwargs.get("current_user")
    user_id = getattr(current_user, "id", "anonymous")
    return f"{namespace}:doc:{doc_id}:user:{user_id}"


async def _invalidate_document_cache(document_id: int) -> None:
    """Evict related document/list caches. Non-fatal if cache backend is unavailable."""
    try:
        backend = FastAPICache.get_backend()
        await backend.clear(namespace="document")
        await backend.clear(namespace="patient-docs")
        await backend.clear(namespace="doctor-patient-docs")
    except Exception:
        pass

@router.get("/documents/{document_id}")
@cache(namespace="document", expire=CACHE_TTL, key_builder=_doc_key_builder)
async def get_document(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Retrieve a specific medical document with AI analysis.
    """
    # Find the document
    document = await db.medicaldocument.find_unique(
        where={'id': document_id},
        include={'users': True}
    )
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if user has access to this document
    if current_user.role == 'patient':
        # Patients can only view their own documents
        if document.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    elif current_user.role == 'doctor':
        # Doctors can view documents of their linked patients
        has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    
    # Use real AI analysis from DB if available, otherwise provide placeholder
    stored_analysis = document.ai_analysis_json
    if stored_analysis and isinstance(stored_analysis, dict):
        cv_result = stored_analysis.get('cv_result', {})
        nlp_result = stored_analysis.get('nlp_result', {})
        ocr_result = stored_analysis.get('ocr_result', '')
        summary_result = stored_analysis.get('summary_result', {})

        classification = cv_result.get('classification', 'Unknown')
        confidence = cv_result.get('confidence', 0)
        probabilities = cv_result.get('probabilities', {})
        recommendation = cv_result.get('recommendation', '')

        # Build findings from probabilities
        findings = []
        for label, prob in probabilities.items():
            findings.append({
                "label": label,
                "confidence": round(prob * 100, 1),
                "description": f"{label} probability from pneumonia classifier."
            })

        # Build summary
        if classification == 'Normal':
            summary_title = "No Pneumonia Detected"
            summary_desc = recommendation
        else:
            summary_title = f"{classification} Detected"
            summary_desc = recommendation

        # Extract prescription/medication data from NLP result
        is_prescription = nlp_result.get('is_prescription', False)
        medications = nlp_result.get('medications', [])
        prescriptions = nlp_result.get('prescriptions', [])
        nlp_entities = nlp_result.get('entities', [])
        nlp_summary = nlp_result.get('summary', '')

        # Extract T5 medical summary
        medical_summary = summary_result.get('medical_summary', '')
        key_findings = summary_result.get('key_findings', [])

        analysis = {
            "summary": {
                "status": "success",
                "title": summary_title,
                "description": summary_desc,
                "classification": classification,
                "confidence": round(confidence * 100, 1),
            },
            "findings": findings,
            "nlp": {
                "summary": nlp_summary,
                "entities": nlp_entities,
                "medications": medications,
                "prescriptions": prescriptions,
                "is_prescription": is_prescription,
            },
            "medical_summary": medical_summary,
            "key_findings": key_findings,
            "ocr_text": ocr_result if isinstance(ocr_result, str) else str(ocr_result),
            "rawResponse": {
                "analysis_id": f"AI-{document_id}",
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "cv_result": cv_result,
                "nlp_result": nlp_result,
                "summary_result": summary_result,
                "model_version": "pneumonia-resnet50-v1"
            }
        }
    else:
        analysis = {
            "summary": {
                "status": "pending",
                "title": "Analysis Not Available",
                "description": "This document has not been analyzed yet. Click 'Analyze' to run AI analysis."
            },
            "findings": [],
            "rawResponse": None
        }
    
    # Build short-lived signed URL and file metadata from storage path
    file_url = ""
    file_name = "unknown"
    if document.file_path:
        storage_path = supabase_storage.to_storage_path(document.file_path)
        file_name = Path(storage_path).name
        file_url = supabase_storage.create_signed_url(storage_path)

    # Detect real file type from extension
    ext = os.path.splitext(file_name)[1].lower()
    file_type_map = {
        '.pdf': 'PDF', '.jpg': 'JPEG', '.jpeg': 'JPEG', '.png': 'PNG',
        '.dcm': 'DICOM', '.dicom': 'DICOM', '.bmp': 'BMP', '.tiff': 'TIFF', '.tif': 'TIFF',
    }
    file_type = file_type_map.get(ext, ext.upper().lstrip('.'))

    # File size is not available without downloading; omit gracefully
    file_size = "Unknown"
    
    return {
        "id": document.id,
        "title": "Medical Document",
        "patient": {
            "name": document.users.email if document.users else "Unknown",
            "id": document.patient_id
        },
        "timestamp": document.upload_timestamp.strftime("%Y-%m-%d %H:%M:%S") if document.upload_timestamp else "",
        "status": "Processed" if stored_analysis else "Pending",
        "fileType": file_type,
        "fileSize": file_size,
        "fileName": file_name,
        "fileUrl": file_url,
        "imageUrl": file_url,
        "ai_analysis": stored_analysis,
        "analysis": analysis
    }


@router.post("/documents/{document_id}/analyze")
async def analyze_document(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Run AI analysis (Pneumonia Classification) on an existing document.
    Triggers OCR, NLP, and CV services and stores results in DB.
    """
    # Find the document
    document = await db.medicaldocument.find_unique(
        where={'id': document_id},
        include={'users': True}
    )

    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )

    # Check access
    if current_user.role == 'patient':
        if document.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    elif current_user.role == 'doctor':
        has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )

    file_path = document.file_path
    if not file_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document file not found"
        )

    tmp_path: str | None = None
    try:
        # Download from Supabase to a temp file for AI processing
        storage_path = supabase_storage.to_storage_path(file_path)
        tmp_path = supabase_storage.download_to_temp(storage_path)

        # Run OCR and CV in parallel
        ocr_task = asyncio.create_task(services.ocr_service(tmp_path))
        cv_task = asyncio.create_task(services.cv_service(tmp_path))

        ocr_result = await ocr_task
        cv_result = await cv_task

        # Run NLP on OCR output
        nlp_result = await services.nlp_service(ocr_result)

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
            "detected_type": final_type
        }

        # Update document with AI analysis
        await db.medicaldocument.update(
            where={'id': document_id},
            data={'ai_analysis_json': Json(aggregated_analysis)}
        )

        return {
            "message": "AI analysis completed successfully",
            "document_id": document_id,
            "analysis": aggregated_analysis
        }
    except Exception as e:
        print(f"\u2717 AI analysis failed for document {document_id}: {e}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"AI analysis failed: {str(e)}"
        )
    finally:
        if tmp_path:
            try:
                os.unlink(tmp_path)
            except OSError:
                pass
        # Evict stale cached GET response
        await _invalidate_document_cache(document_id)


@router.post("/documents/{document_id}/verify")
async def verify_document(
    document_id: int,
    payload: VerifyDocumentRequest | None = Body(default=None),
    notes: Optional[str] = Query(default=None),
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Verify and sign off on a document analysis.
    Only doctors can verify documents.
    """
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can verify documents"
        )
    
    # Find the document
    document = await db.medicaldocument.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    effective_notes = payload.notes if payload and payload.notes is not None else notes

    # Update document with verification
    verified_at = datetime.utcnow()
    updated_doc = await db.medicaldocument.update(
        where={'id': document_id},
        data={
            'verified_by': current_user.id,
            'verified_at': verified_at,
            'verification_notes': effective_notes
        }
    )
    
    await _invalidate_document_cache(document_id)
    return {
        "message": "Document verified successfully",
        "verified_by": current_user.email,
        "verified_at": verified_at.isoformat(),
        "notes": effective_notes
    }



@router.post("/documents/{document_id}/notes")
async def add_clinical_note(
    document_id: int,
    payload: ClinicalNoteRequest | None = Body(default=None),
    note: Optional[str] = Query(default=None),
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Add a clinical note to a document.
    """
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can add clinical notes"
        )
    
    effective_note = payload.note if payload and payload.note is not None else note
    if not effective_note or not effective_note.strip():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Clinical note cannot be empty"
        )

    # Find the document
    document = await db.medicaldocument.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Get existing notes or initialize empty list
    existing_notes = document.clinical_notes if document.clinical_notes else []
    
    # Add new note
    added_at = datetime.utcnow()
    new_note = {
        "note": effective_note,
        "added_by": current_user.email,
        "added_by_id": current_user.id,
        "added_at": added_at.isoformat()
    }
    
    # Append to existing notes
    if isinstance(existing_notes, list):
        existing_notes.append(new_note)
    else:
        existing_notes = [new_note]
    
    # Update document with new note
    await db.medicaldocument.update(
        where={'id': document_id},
        data={'clinical_notes': Json(existing_notes)}
    )
    await _invalidate_document_cache(document_id)
    
    return {
        "message": "Clinical note added successfully",
        "note": effective_note,
        "added_by": current_user.email,
        "added_at": added_at.isoformat()
    }


@router.post("/documents/{document_id}/archive")
async def archive_document(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Archive a document. Only doctors can archive documents.
    """
    if current_user.role != 'doctor':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only doctors can archive documents"
        )
    
    # Find the document
    document = await db.medicaldocument.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
    if not has_access:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Update document as archived
    archived_at = datetime.utcnow()
    await db.medicaldocument.update(
        where={'id': document_id},
        data={
            'archived': True,
            'archived_at': archived_at,
            'archived_by': current_user.id
        }
    )
    
    await _invalidate_document_cache(document_id)
    return {
        "message": "Document archived successfully",
        "archived_by": current_user.email,
        "archived_at": archived_at.isoformat()
    }



@router.get("/documents/{document_id}/download")
async def download_document(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Download a document file.
    """
    # Find the document
    document = await db.medicaldocument.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if user has access to this document
    if current_user.role == 'patient':
        if document.patient_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    elif current_user.role == 'doctor':
        has_access = await doctor_has_patient_access(db, current_user.id, document.patient_id)
        if not has_access:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    
    # Check if file path exists in DB
    file_path = document.file_path
    if not file_path:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found"
        )

    # Redirect to a short-lived signed URL for private object access
    storage_path = supabase_storage.to_storage_path(file_path)
    signed_url = supabase_storage.create_signed_url(storage_path)
    return RedirectResponse(url=signed_url)
