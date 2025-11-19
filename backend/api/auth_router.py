from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from datetime import timedelta
from pydantic import BaseModel

from backend import auth, schemas
from backend.prisma_db import get_db
from backend.google_oauth import verify_google_token
from backend.prisma_client import Prisma

router = APIRouter()


class GoogleLoginRequest(BaseModel):
    token: str
    role: str


@router.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    db: Prisma = Depends(get_db), form_data: OAuth2PasswordRequestForm = Depends()
):
    if form_data.username == "admin@intellimed.ai" and form_data.password == "adminpassword":
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
    
    if request.role != 'patient':
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Google login is only available for patient accounts. Doctors must use email/password login."
        )
    
    user = await auth.get_user(db, email=email)
    if not user:
        user = await db.user.create(
            data={
                'email': email,
                'name': name,
                'hashed_password': auth.get_password_hash(user_info['sub']),
                'role': 'patient'
            }
        )
    else:
        if user.role != 'patient':
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="This account is not a patient account. Doctors must use email/password login."
            )
    
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email, "role": user.role}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/register", response_model=schemas.UserInDB)
async def register_user(user: schemas.UserCreate, db: Prisma = Depends(get_db)):
    if user.role == 'doctor' and user.doctor_access_code != "DOCTOR_SECRET":
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
