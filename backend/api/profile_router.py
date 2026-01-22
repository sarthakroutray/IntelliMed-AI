from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from typing import Optional
from datetime import date

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import auth
from prisma_db import get_db
from prisma_client import Prisma

router = APIRouter()


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    phone: Optional[str] = None
    date_of_birth: Optional[date] = None
    gender: Optional[str] = None
    address: Optional[str] = None
    emergency_contact: Optional[str] = None
    emergency_phone: Optional[str] = None
    blood_type: Optional[str] = None
    allergies: Optional[str] = None
    chronic_conditions: Optional[str] = None


@router.get("/profile")
async def get_profile(
    current_user: dict = Depends(auth.get_current_user),
    db: Prisma = Depends(get_db)
):
    """Get current user profile"""
    try:
        user = await db.user.find_unique(where={"id": current_user["id"]})
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        
        # Return profile data (excluding sensitive fields)
        return {
            "id": user.id,
            "email": user.email,
            "name": user.name,
            "role": user.role,
            "phone": user.phone,
            "date_of_birth": user.date_of_birth.isoformat() if user.date_of_birth else None,
            "gender": user.gender,
            "address": user.address,
            "emergency_contact": user.emergency_contact,
            "emergency_phone": user.emergency_phone,
            "blood_type": user.blood_type,
            "allergies": user.allergies,
            "chronic_conditions": user.chronic_conditions,
            "created_at": user.created_at.isoformat() if user.created_at else None
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch profile: {str(e)}"
        )


@router.put("/profile")
async def update_profile(
    profile_data: UpdateProfileRequest,
    current_user: dict = Depends(auth.get_current_user),
    db: Prisma = Depends(get_db)
):
    """Update current user profile"""
    try:
        # Build update data dict, excluding None values
        update_data = {
            k: v for k, v in profile_data.dict().items() 
            if v is not None
        }
        
        if not update_data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="No data provided for update"
            )
        
        # Update user profile
        updated_user = await db.user.update(
            where={"id": current_user["id"]},
            data=update_data
        )
        
        return {
            "message": "Profile updated successfully",
            "user": {
                "id": updated_user.id,
                "email": updated_user.email,
                "name": updated_user.name,
                "role": updated_user.role,
                "phone": updated_user.phone,
                "date_of_birth": updated_user.date_of_birth.isoformat() if updated_user.date_of_birth else None,
                "gender": updated_user.gender,
                "address": updated_user.address,
                "emergency_contact": updated_user.emergency_contact,
                "emergency_phone": updated_user.emergency_phone,
                "blood_type": updated_user.blood_type,
                "allergies": updated_user.allergies,
                "chronic_conditions": updated_user.chronic_conditions
            }
        }
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )
