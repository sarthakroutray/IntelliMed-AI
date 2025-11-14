"""
Prisma Utilities - Provides database operations that will work with Prisma/PostgreSQL

This module uses raw SQL queries that match Prisma's behavior.
It serves as a bridge between the Python FastAPI backend and Prisma schema.

To use this instead of SQLAlchemy:
1. Replace: from backend.database import get_db, Session
   With: from backend.prisma_utils import get_db

2. Replace: db.query(Model).filter(...).first()
   With: await db.find_user(email=...)

3. Replace: db.add(obj); db.commit(); db.refresh(obj)
   With: await db.create_user(...)
"""
import os
import json
import asyncio
from typing import Optional, List, Dict, Any
from datetime import datetime
from enum import Enum
from contextlib import contextmanager

import psycopg2
from psycopg2.extras import RealDictCursor, Json
from urllib.parse import urlparse

# Constants
class Role(str, Enum):
    patient = "patient"
    doctor = "doctor"

class DatabaseConnection:
    """Manages PostgreSQL connection"""
    
    def __init__(self, db_url: Optional[str] = None):
        self.db_url = db_url or os.getenv("DATABASE_URL")
        if not self.db_url:
            raise ValueError("DATABASE_URL not set in environment")
        self.conn = None
    
    def connect(self):
        """Establish database connection"""
        if self.conn:
            return self.conn
        
        try:
            parsed = urlparse(self.db_url)
            self.conn = psycopg2.connect(
                dbname=parsed.path.lstrip('/'),
                user=parsed.username,
                password=parsed.password,
                host=parsed.hostname,
                port=parsed.port or 5432,
                sslmode='require',
                cursor_factory=RealDictCursor
            )
            return self.conn
        except psycopg2.OperationalError as e:
            print(f"Database connection error: {e}")
            raise
    
    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()
            self.conn = None
    
    @contextmanager
    def cursor(self):
        """Context manager for database cursor"""
        conn = self.connect()
        cur = conn.cursor()
        try:
            yield cur
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            cur.close()

class PrismaUtilities:
    """Database operations matching Prisma API"""
    
    def __init__(self, db_connection: DatabaseConnection):
        self.db = db_connection
    
    # ==================== User Operations ====================
    
    def find_user_by_email(self, email: str) -> Optional[Dict[str, Any]]:
        """Find user by email"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT * FROM "users" WHERE email = %s',
                (email,)
            )
            result = cur.fetchone()
            return dict(result) if result else None
    
    def find_user_by_id(self, user_id: int) -> Optional[Dict[str, Any]]:
        """Find user by ID"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT * FROM "users" WHERE id = %s',
                (user_id,)
            )
            result = cur.fetchone()
            return dict(result) if result else None
    
    def find_all_patients(self) -> List[Dict[str, Any]]:
        """Get all patient users"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT * FROM "users" WHERE role = %s',
                (Role.patient.value,)
            )
            return [dict(row) for row in cur.fetchall()]
    
    def create_user(self, email: str, hashed_password: str, role: str) -> Dict[str, Any]:
        """Create a new user"""
        with self.db.cursor() as cur:
            cur.execute(
                '''INSERT INTO "users" (email, "hashedPassword", role)
                   VALUES (%s, %s, %s)
                   RETURNING *''',
                (email, hashed_password, role)
            )
            result = cur.fetchone()
            return dict(result)
    
    def user_exists(self, email: str) -> bool:
        """Check if user exists"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT 1 FROM "users" WHERE email = %s',
                (email,)
            )
            return cur.fetchone() is not None
    
    # ==================== Medical Document Operations ====================
    
    def create_document(
        self,
        patient_id: int,
        file_path: str,
        ai_analysis_json: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """Create a medical document"""
        with self.db.cursor() as cur:
            cur.execute(
                '''INSERT INTO "medical_documents" ("patientId", "filePath", "aiAnalysisJson")
                   VALUES (%s, %s, %s)
                   RETURNING *''',
                (patient_id, file_path, Json(ai_analysis_json) if ai_analysis_json else None)
            )
            result = cur.fetchone()
            return dict(result)
    
    def find_documents_by_patient(self, patient_id: int) -> List[Dict[str, Any]]:
        """Get all documents for a patient"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT * FROM "medical_documents" WHERE "patientId" = %s ORDER BY "uploadTimestamp" DESC',
                (patient_id,)
            )
            return [dict(row) for row in cur.fetchall()]
    
    def find_document_by_id(self, doc_id: int) -> Optional[Dict[str, Any]]:
        """Find document by ID"""
        with self.db.cursor() as cur:
            cur.execute(
                'SELECT * FROM "medical_documents" WHERE id = %s',
                (doc_id,)
            )
            result = cur.fetchone()
            return dict(result) if result else None

# Global database instance
_db_connection: Optional[DatabaseConnection] = None
_prisma_utils: Optional[PrismaUtilities] = None

def get_prisma() -> PrismaUtilities:
    """Get global Prisma utilities instance"""
    global _db_connection, _prisma_utils
    
    if not _db_connection:
        _db_connection = DatabaseConnection()
    if not _prisma_utils:
        _prisma_utils = PrismaUtilities(_db_connection)
    
    return _prisma_utils

def get_db():
    """Dependency injection for FastAPI"""
    return get_prisma()

def init_database():
    """Initialize database connection (call from main.py)"""
    try:
        db = get_prisma()
        # Test connection
        db.db.connect()
        print("✅ Database connection successful")
    except Exception as e:
        print(f"⚠️  Database connection failed: {e}")
        print("This is expected if Supabase is not yet accessible.")

def close_database():
    """Close database connection (call from main.py shutdown)"""
    global _db_connection
    if _db_connection:
        _db_connection.close()
        _db_connection = None
