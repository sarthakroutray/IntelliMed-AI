from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from datetime import timedelta
from pydantic import BaseModel

from backend import auth, models, schemas
from backend.database import get_db
from backend.google_oauth import verify_google_token

router = APIRouter()


class GoogleLoginRequest(BaseModel):
    token: str


@router.post("/token", response_model=schemas.Token)
async def login_for_access_token(
    db: Session = Depends(get_db), form_data: OAuth2PasswordRequestForm = Depends()
):
    # Hardcoded admin credentials for development
    if form_data.username == "admin@intellimed.ai" and form_data.password == "adminpassword":
        access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
        # Note: In a real app, the role should be part of the user data from the DB
        access_token = auth.create_access_token(
            data={"sub": form_data.username}, expires_delta=access_token_expires
        )
        return {"access_token": access_token, "token_type": "bearer"}

    user = auth.get_user(db, email=form_data.username)
    if not user or not auth.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/google-login", response_model=schemas.Token)
async def google_login(request: GoogleLoginRequest, db: Session = Depends(get_db)):
    """
    Login using Google OAuth2 token.
    
    Args:
        request: Contains the Google ID token from frontend
        db: Database session
        
    Returns:
        Access token for authenticated requests
    """
    # Verify the Google token
    user_info = verify_google_token(request.token)
    
    email = user_info['email']
    name = user_info.get('name', '')
    
    # Check if user exists, if not create them
    user = auth.get_user(db, email=email)
    if not user:
        # Create new user with doctor role by default
        db_user = models.User(
            email=email,
            hashed_password=auth.get_password_hash(user_info['sub']),  # Use Google's sub as password hash
            role=models.Role.doctor
        )
        db.add(db_user)
        db.commit()
        db.refresh(db_user)
        user = db_user
    
    # Create access token
    access_token_expires = timedelta(minutes=auth.ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = auth.create_access_token(
        data={"sub": user.email}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/register", response_model=schemas.UserInDB)
def register_user(user: schemas.UserCreate, db: Session = Depends(get_db)):
    db_user = auth.get_user(db, email=user.email)
    if db_user:
        raise HTTPException(
            status_code=400, detail="Email already registered"
        )
    hashed_password = auth.get_password_hash(user.password)
    db_user = models.User(
        email=user.email, hashed_password=hashed_password, role=user.role
    )
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user
