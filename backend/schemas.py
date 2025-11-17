from pydantic import BaseModel, EmailStr
from typing import Optional, Dict, Any
from datetime import datetime
from backend.prisma_client.enums import role_enum as Role


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    role: Role
    name: Optional[str] = None
    doctor_access_code: Optional[str] = None


class UserInDB(BaseModel):
    id: int
    email: EmailStr
    name: Optional[str] = None
    role: Role

    class Config:
        from_attributes = True

class User(UserInDB):
    pass

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
        from_attributes = True

class DocumentDetail(DocumentInfo):
    id: int
    file_url: str
    analysis_status: str
