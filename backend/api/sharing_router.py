from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User
from prisma_client import Prisma

router = APIRouter()

@router.post("/documents/{document_id}/share/{doctor_id}")
async def share_document(
    document_id: int,
    doctor_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Share a document with a specific doctor.
    Only the document owner (patient) can share it.
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can share documents",
        )

    # Verify the document belongs to the current user
    document = await db.medicaldocument.find_unique(
        where={'id': document_id}
    )
    
    if not document or document.patient_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to share this document",
        )

    # Verify the doctor is linked to this patient
    link = await db.doctorpatient.find_first(
        where={
            'doctor_id': doctor_id,
            'patient_id': current_user.id,
        }
    )
    
    if not link:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="This doctor is not linked to you",
        )

    try:
        # Create or update the share record
        await db.documentshare.upsert(
            where={
                'document_id_doctor_id': {
                    'document_id': document_id,
                    'doctor_id': doctor_id,
                }
            },
            data={
                'create': {
                    'document_id': document_id,
                    'doctor_id': doctor_id,
                },
                'update': {},
            }
        )
        
        print(f"✓ Document {document_id} shared with doctor {doctor_id}")
        return {"message": "Document shared successfully"}
    except Exception as e:
        print(f"✗ Failed to share document: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to share document: {str(e)}"
        )


@router.delete("/documents/{document_id}/share/{doctor_id}")
async def unshare_document(
    document_id: int,
    doctor_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Revoke document access from a specific doctor.
    Only the document owner (patient) can revoke access.
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can unshare documents",
        )

    # Verify the document belongs to the current user
    document = await db.medicaldocument.find_unique(
        where={'id': document_id}
    )
    
    if not document or document.patient_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to unshare this document",
        )

    try:
        await db.documentshare.delete(
            where={
                'document_id_doctor_id': {
                    'document_id': document_id,
                    'doctor_id': doctor_id,
                }
            }
        )
        
        print(f"✓ Document {document_id} unshared with doctor {doctor_id}")
        return {"message": "Document access revoked successfully"}
    except Exception as e:
        print(f"✗ Failed to unshare document: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to unshare document: {str(e)}"
        )


@router.get("/documents/{document_id}/shared-doctors")
async def get_shared_doctors(
    document_id: int,
    db: Prisma = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """
    Get list of doctors the document is shared with.
    Only the document owner can view this.
    """
    if current_user.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only patients can view share information",
        )

    # Verify the document belongs to the current user
    document = await db.medicaldocument.find_unique(
        where={'id': document_id}
    )
    
    if not document or document.patient_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="You don't have permission to view this document's shares",
        )

    try:
        shares = await db.documentshare.find_many(
            where={'document_id': document_id},
            include={'doctor': True}
        )
        
        return [{'doctor_id': share.doctor_id, 'doctor_email': share.doctor.email} for share in shares]
    except Exception as e:
        print(f"✗ Failed to fetch shared doctors: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch shared doctors: {str(e)}"
        )
