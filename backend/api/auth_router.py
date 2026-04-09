from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from datetime import timedelta
from pydantic import BaseModel
import os

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))

import auth
import schemas
from prisma_db import get_db
from google_oauth import verify_google_token
from prisma_client import Prisma

router = APIRouter()
DOCTOR_ACCESS_CODE = os.getenv("DOCTOR_ACCESS_CODE", "")
ADMIN_EMAIL = os.getenv("ADMIN_EMAIL", "admin@intellimed.ai")
ADMIN_PASSWORD = os.getenv("ADMIN_PASSWORD")


class GoogleLoginRequest(BaseModel):
    token: str
    role: str


@router.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    db: Prisma = Depends(get_db), form_data: OAuth2PasswordRequestForm = Depends()
):
    if ADMIN_PASSWORD and form_data.username == ADMIN_EMAIL and form_data.password == ADMIN_PASSWORD:
        access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
        access_token = auth.create_access_token(
            data={"sub": form_data.username, "role": "admin"}, expires_delta=access_token_expires
        )
        return {"access_token": access_token, "token_type": "bearer"}

    user = await auth.get_user(db, email=form_data.username)
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/google-login", response_model=schemas.Token)
async def google_login(request: GoogleLoginRequest, db: Prisma = Depends(get_db)):
    user_info = verify_google_token(request.token)
    
    email = user_info['email']
    name = user_info.get('name', '')
    
    # Validate role
    if request.role not in ['patient', 'doctor']:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Invalid role. Must be 'patient' or 'doctor'."
        )
    
    user = await auth.get_user(db, email=email)
    if not user:
        # Create new user with the requested role
        user = await db.user.create(
            data={
                'email': email,
                'name': name,
                'hashed_password': auth.get_password_hash(user_info['sub']),
                'role': request.role
            }
        )
    else:
        # Check if existing user's role matches the requested role
        if user.role != request.role:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"This account is registered as a {user.role}. Please sign in with the correct role."
            )
    
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/register", response_model=schemas.UserInDB)
async def register_user(user: schemas.UserCreate, db: Prisma = Depends(get_db)):
    if user.role == 'doctor':
        if not DOCTOR_ACCESS_CODE:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Doctor registration is not configured",
            )
        if user.doctor_access_code != DOCTOR_ACCESS_CODE:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Invalid doctor access code.",
            )

    db_user = await auth.get_user(db, email=user.email)
    if db_user:
        raise HTTPException(
            status_code=400, detail="Email already registered"
        )
    
    hashed_password = auth.get_password_hash(user.password)
    
    db_user = await db.user.create(
        data={
            'email': user.email,
            'name': user.name,
            'hashed_password': hashed_password,
            'role': user.role
        }
    )
    return db_user
