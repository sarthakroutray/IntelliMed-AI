import os
from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import date, datetime
from fastapi_cache import FastAPICache
from fastapi_cache.decorator import cache

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import auth
from prisma_db import get_db
from prisma_client import Prisma
from request_cache import clear_cache_namespace, clear_cache_key

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
        await clear_cache_namespace("profile")
        await clear_cache_key("profile", f"user:{user_id}")
    except Exception:
        pass


class UpdateProfileRequest(BaseModel):
    name: Optional[str] = None
    email: Optional[EmailStr] = None
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


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class DeleteAccountRequest(BaseModel):
    password: Optional[str] = None


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
            "date_of_birth": current_user.date_of_birth.strftime("%Y-%m-%d") if current_user.date_of_birth else None,
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
        update_data = {}
        for k, v in profile_data.dict().items():
            if v is not None:
                if k == "date_of_birth" and isinstance(v, date) and not isinstance(v, datetime):
                    update_data[k] = datetime.combine(v, datetime.min.time())
                else:
                    update_data[k] = v
        
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

        auth.invalidate_cached_user(email=current_user.email, user_id=current_user.id)
        if updated_user.email != current_user.email:
            auth.invalidate_cached_user(email=updated_user.email)
        await _invalidate_profile_cache(current_user.id)

        return {
            "message": "Profile updated successfully",
            "user": {
                "id": updated_user.id,
                "email": updated_user.email,
                "name": updated_user.name,
                "role": updated_user.role,
                "phone": updated_user.phone,
                "date_of_birth": updated_user.date_of_birth.strftime("%Y-%m-%d") if updated_user.date_of_birth else None,
                "gender": updated_user.gender,
                "address": updated_user.address,
                "emergency_contact": updated_user.emergency_contact,
                "emergency_phone": updated_user.emergency_phone,
                "blood_type": updated_user.blood_type,
                "allergies": updated_user.allergies,
                "chronic_conditions": updated_user.chronic_conditions,
                "dark_mode": updated_user.dark_mode,
                "email_notifications": updated_user.email_notifications,
                "push_notifications": updated_user.push_notifications,
            }
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update profile: {str(e)}"
        )


@router.post("/change-password")
async def change_password(
    payload: ChangePasswordRequest,
    current_user=Depends(auth.get_current_user),
    db: Prisma = Depends(get_db),
):
    """Change the current user's password after verifying the current one."""
    if current_user.id == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin password cannot be changed here",
        )
    if not payload.new_password or len(payload.new_password) < 8:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="New password must be at least 8 characters long",
        )
    user = await db.user.find_unique(where={"id": current_user.id})
    if not user or not auth.verify_password(payload.current_password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Current password is incorrect",
        )
    hashed = auth.get_password_hash(payload.new_password)
    await db.user.update(where={"id": current_user.id}, data={"hashed_password": hashed})
    auth.invalidate_cached_user(email=current_user.email, user_id=current_user.id)
    await _invalidate_profile_cache(current_user.id)
    return {"message": "Password changed successfully"}


@router.delete("/account")
async def delete_account(
    current_user=Depends(auth.get_current_user),
    db: Prisma = Depends(get_db),
):
    """Delete the current user's account and owned records."""
    if current_user.id == 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Admin account cannot be deleted",
        )
    try:
        import asyncio as _asyncio
        import supabase_storage as _storage

        async def _delete_owned_files() -> None:
            try:
                docs = await db.medicaldocument.find_many(where={"patient_id": current_user.id})
            except Exception:
                docs = []
            try:
                reports = await db.labreport.find_many(where={"patient_id": current_user.id})
            except Exception:
                reports = []
            for row in list(docs) + list(reports):
                path = getattr(row, "file_path", None)
                if not path or path.startswith("app-structured/"):
                    continue
                try:
                    storage_path = _storage.to_storage_path(path)
                    await _asyncio.to_thread(_storage.delete_file, storage_path)
                except Exception:
                    pass

        await _delete_owned_files()
        await db.documentshare.delete_many(where={"doctor_id": current_user.id})
        await db.doctorpatient.delete_many(
            where={"OR": [{"doctor_id": current_user.id}, {"patient_id": current_user.id}]}
        )
        await db.medicaldocument.delete_many(where={"patient_id": current_user.id})
        await db.labreport.delete_many(where={"patient_id": current_user.id})
        await db.user.delete(where={"id": current_user.id})
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to delete account: {str(e)}",
        )
    finally:
        auth.invalidate_cached_user(email=current_user.email, user_id=current_user.id)
        await _invalidate_profile_cache(current_user.id)
    return {"message": "Account deleted successfully"}
