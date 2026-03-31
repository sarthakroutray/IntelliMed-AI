import os
from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel
from typing import Optional
from datetime import date
from fastapi_cache import FastAPICache
from fastapi_cache.decorator import cache

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import auth
from prisma_db import get_db
from prisma_client import Prisma

router = APIRouter()

CACHE_TTL = int(os.getenv("CACHE_TTL_SECONDS", "300"))


def _profile_key_builder(
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
    return f"{namespace}:user:{user_id}"


async def _invalidate_profile_cache(user_id: int) -> None:
    try:
        key = f"profile:user:{user_id}"
        await FastAPICache.get_backend().clear(namespace=None, key=key)
    except Exception:
        pass


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
    dark_mode: Optional[bool] = None
    email_notifications: Optional[bool] = None
    push_notifications: Optional[bool] = None


@router.get("/profile")
@cache(namespace="profile", expire=CACHE_TTL, key_builder=_profile_key_builder)
async def get_profile(
    current_user = Depends(auth.get_current_user)
):
    """Get current user profile"""
    try:
        # Return profile data (excluding sensitive fields)
        return {
            "id": current_user.id,
            "email": current_user.email,
            "name": current_user.name,
            "role": current_user.role,
            "phone": current_user.phone,
            "date_of_birth": current_user.date_of_birth.isoformat() if current_user.date_of_birth else None,
            "gender": current_user.gender,
            "address": current_user.address,
            "emergency_contact": current_user.emergency_contact,
            "emergency_phone": current_user.emergency_phone,
            "blood_type": current_user.blood_type,
            "allergies": current_user.allergies,
            "chronic_conditions": current_user.chronic_conditions,
            "dark_mode": current_user.dark_mode,
            "email_notifications": current_user.email_notifications,
            "push_notifications": current_user.push_notifications,
            "created_at": current_user.created_at.isoformat() if current_user.created_at else None
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to fetch profile: {str(e)}"
        )


@router.put("/profile")
async def update_profile(
    profile_data: UpdateProfileRequest,
    current_user = Depends(auth.get_current_user),
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
            where={"id": current_user.id},
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
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )
    finally:
        auth.invalidate_cached_user(user_id=current_user.id)
        await _invalidate_profile_cache(current_user.id)
