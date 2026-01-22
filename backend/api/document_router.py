from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from fastapi.responses import FileResponse
from datetime import datetime
import sys
import os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentDetail
from prisma_client import Prisma, Json

router = APIRouter()

@router.get("/documents/{document_id}")
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
        link = await db.doctorpatient.find_first(
            where={
                'doctor_id': current_user.id,
                'patient_id': document.patient_id
            }
        )
        if not link:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    
    # Mock AI analysis data (replace with actual AI service call)
    analysis = {
        "summary": {
            "status": "success",
            "title": "No Urgent Abnormalities",
            "description": "AI analysis indicates lung fields are clear. No signs of pneumothorax or acute consolidation."
        },
        "findings": [
            {"label": "Calcification", "confidence": 63, "description": "Possible benign calcified granuloma in the right upper lobe."},
            {"label": "Pleural Effusion", "confidence": 12, "description": ""},
            {"label": "Infiltration", "confidence": 5, "description": ""}
        ],
        "metrics": {
            "ctrRatio": "0.42",
            "lungVolume": "4.2 L"
        },
        "rawResponse": {
            "analysis_id": f"AI-{document_id}",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "findings": [
                {"label": "Calcification", "confidence": 0.63},
                {"label": "Pleural Effusion", "confidence": 0.12}
            ],
            "model_version": "v4.2.1"
        }
    }
    
    return {
        "id": document.id,
        "title": "Medical Document",
        "patient": {
            "name": document.users.email if document.users else "Unknown",
            "id": document.patient_id
        },
        "timestamp": document.upload_timestamp.strftime("%Y-%m-%d %H:%M:%S") if document.upload_timestamp else "",
        "status": "Processed",
        "fileType": "DICOM",
        "fileSize": "2.4 MB",  # Calculate actual file size if needed
        "fileName": document.file_path.split('/')[-1] if document.file_path else "unknown",
        "fileUrl": document.file_path,
        "imageUrl": document.file_path,  # Use actual file path
        "analysis": analysis
    }


@router.post("/documents/{document_id}/verify")
async def verify_document(
    document_id: int,
    notes: Optional[str] = None,
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
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': document.patient_id
        }
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Update document with verification
    verified_at = datetime.utcnow()
    updated_doc = await db.medicaldocument.update(
        where={'id': document_id},
        data={
            'verified_by': current_user.id,
            'verified_at': verified_at,
            'verification_notes': notes
        }
    )
    
    return {
        "message": "Document verified successfully",
        "verified_by": current_user.email,
        "verified_at": verified_at.isoformat(),
        "notes": notes
    }


@router.post("/documents/{document_id}/notes")
async def add_clinical_note(
    document_id: int,
    note: str,
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
    
    # Find the document
    document = await db.medicaldocument.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': document.patient_id
        }
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Get existing notes or initialize empty list
    existing_notes = document.clinical_notes if document.clinical_notes else []
    
    # Add new note
    added_at = datetime.utcnow()
    new_note = {
        "note": note,
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
    
    return {
        "message": "Clinical note added successfully",
        "note": note,
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
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': document.patient_id
        }
    )
    if not link:
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
        link = await db.doctorpatient.find_first(
            where={
                'doctor_id': current_user.id,
                'patient_id': document.patient_id
            }
        )
        if not link:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    
    # Check if file exists
    file_path = document.file_path
    if not os.path.exists(file_path):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="File not found on server"
        )
    
    # Return file for download
    filename = os.path.basename(file_path)
    return FileResponse(
        path=file_path,
        filename=filename,
        media_type='application/octet-stream'
    )
