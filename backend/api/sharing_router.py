import logging
from typing import List
import os
from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi_cache import FastAPICache
from fastapi_cache.decorator import cache
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

from auth import get_current_user
from prisma_db import get_db
from schemas import User
from prisma_client import Prisma
from request_cache import clear_cache_namespace, clear_cache_key

logger = logging.getLogger(__name__)

router = APIRouter()
CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))


def _shared_doctors_key_builder(
    func,
    namespace: str = "",
    *,
    request: Request = None,
    response=None,
    args: tuple = (),
    kwargs: dict = {},
) -> str:
    current_user = kwargs.get("current_user")
    user_id = getattr(current_user, "id", "anonymous")
    document_id = kwargs.get("document_id", "unknown")
    return f"{namespace}:doc:{document_id}:user:{user_id}"


async def _invalidate_shared_doctors_cache(document_id: int, user_id: int) -> None:
    try:
        await clear_cache_namespace("shared-doctors")
        await clear_cache_key("shared-doctors", f"doc:{document_id}:user:{user_id}")
        await clear_cache_namespace("doctor-patient-docs")
        await clear_cache_namespace("doctor-documents")
    except Exception:
        pass

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
        # Idempotent grant: skip the upsert when the row already exists so a
        # repeated Share click (or a double-tap race) can't raise a unique
        # violation. The upsert path stays as a fallback for races.
        existing = await db.documentshare.find_first(
            where={
                'document_id': document_id,
                'doctor_id': doctor_id,
            }
        )
        if existing is None:
            try:
                await db.documentshare.create(
                    data={
                        'document_id': document_id,
                        'doctor_id': doctor_id,
                    }
                )
            except Exception as create_err:
                already = await db.documentshare.find_first(
                    where={
                        'document_id': document_id,
                        'doctor_id': doctor_id,
                    }
                )
                if already is None:
                    raise create_err
        await _invalidate_shared_doctors_cache(document_id, current_user.id)
        
        logger.info("✓ Document %s shared with doctor %s", document_id, doctor_id)
        return {"message": "Document shared successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("✗ Failed to share document: %s", e)
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
        await db.documentshare.delete_many(
            where={
                'document_id': document_id,
                'doctor_id': doctor_id,
            }
        )
        await _invalidate_shared_doctors_cache(document_id, current_user.id)
        
        logger.info("✓ Document %s unshared with doctor %s", document_id, doctor_id)
        return {"message": "Document access revoked successfully"}
    except HTTPException:
        raise
    except Exception as e:
        logger.error("✗ Failed to unshare document: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to unshare document: {str(e)}"
        )


@router.get("/documents/{document_id}/shared-doctors")
@cache(namespace="shared-doctors", expire=CACHE_TTL, key_builder=_shared_doctors_key_builder)
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
        
        return [
            {
                'doctor_id': share.doctor_id,
                'doctor_email': share.doctor.email if share.doctor else 'Unknown',
                'doctor_name': share.doctor.name if (share.doctor and share.doctor.name) else None,
            }
            for share in shares
        ]
    except HTTPException:
        raise
    except Exception as e:
        logger.error("✗ Failed to fetch shared doctors: %s", e)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch shared doctors: {str(e)}"
        )
