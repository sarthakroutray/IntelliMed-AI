from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any
from datetime import datetime
from backend.models import Role


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    role: Role


class UserInDB(BaseModel):
    id: int
    email: EmailStr
    role: Role

    class Config:
        orm_mode = True


class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    email: Optional[str] = None


class DocumentInfo(BaseModel):
    filename: str
    upload_timestamp: datetime
    ai_analysis: Optional[Dict[str, Any]]

    class Config:
        orm_mode = True
