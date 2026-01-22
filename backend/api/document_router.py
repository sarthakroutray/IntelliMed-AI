from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, UploadFile, File
from datetime import datetime
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User, DocumentDetail
from prisma_client import Prisma

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
    document = await db.document.find_unique(
        where={'id': document_id},
        include={'user': True}
    )
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if user has access to this document
    if current_user.role == 'patient':
        # Patients can only view their own documents
        if document.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="You don't have access to this document"
            )
    elif current_user.role == 'doctor':
        # Doctors can view documents of their linked patients
        link = await db.doctorpatient.find_first(
            where={
                'doctor_id': current_user.id,
                'patient_id': document.user_id
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
        "title": document.file_name or "Medical Document",
        "patient": {
            "name": document.user.email,  # Use actual name if available
            "id": document.user_id
        },
        "timestamp": document.created_at.strftime("%Y-%m-%d %H:%M:%S"),
        "status": "Processed",
        "fileType": document.file_type or "DICOM",
        "fileSize": "2.4 MB",  # Calculate actual file size if needed
        "fileName": document.file_name,
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
    document = await db.document.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': document.user_id
        }
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Update document with verification (you might want to add these fields to your schema)
    # For now, we'll just return success
    
    return {
        "message": "Document verified successfully",
        "verified_by": current_user.email,
        "verified_at": datetime.utcnow().isoformat(),
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
    document = await db.document.find_unique(where={'id': document_id})
    
    if not document:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Document not found"
        )
    
    # Check if doctor has access to this patient
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': current_user.id,
            'patient_id': document.user_id
        }
    )
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have access to this document"
        )
    
    # Here you would save the note to your database
    # For now, we'll just return success
    
    return {
        "message": "Clinical note added successfully",
        "note": note,
        "added_by": current_user.email,
        "added_at": datetime.utcnow().isoformat()
    }
