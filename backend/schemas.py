from pydantic import BaseModel, EmailStr, ConfigDict
from typing import Optional, Dict, Any
from datetime import datetime
from prisma_client.enums import role_enum as Role


class UserCreate(BaseModel):
    email: EmailStr
    password: str
    role: Role
    name: Optional[str] = None
    doctor_access_code: Optional[str] = None


class UserInDB(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: EmailStr
    name: Optional[str] = None
    role: Role

class User(UserInDB):
    pass

class Token(BaseModel):
    access_token: str
    token_type: str


class TokenData(BaseModel):
    email: Optional[str] = None


class DocumentInfo(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    filename: str
    upload_timestamp: Optional[datetime] = None
    ai_analysis: Optional[Dict[str, Any]] = None

class DocumentDetail(DocumentInfo):
    file_url: str
    analysis_status: str = "processed"
