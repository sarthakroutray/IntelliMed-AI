"""
Seed database with sample data using direct SQL queries.

This script populates the database with:
- 1 doctor account
- 3 patient accounts
- Sample medical documents for patients

Note: This script will use direct PostgreSQL connections since the Prisma
JavaScript client isn't directly callable from Python. This is a temporary
solution until the backend is fully migrated to use Prisma.

To run: python seed_data_prisma.py
"""
import os
import sys
from datetime import datetime
import psycopg2
from psycopg2.extras import Json
import json
from dotenv import load_dotenv

# Load environment variables
load_dotenv(os.path.join(os.path.dirname(__file__), ".env"))

def get_connection():
    """Establish database connection"""
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print("ERROR: DATABASE_URL not set")
        sys.exit(1)
    
    try:
        # Parse connection string
        # Format: postgresql://user:password@host:port/database
        from urllib.parse import urlparse
        parsed = urlparse(db_url)
        
        conn = psycopg2.connect(
            dbname=parsed.path.lstrip('/'),
            user=parsed.username,
            password=parsed.password,
            host=parsed.hostname,
            port=parsed.port or 5432,
            sslmode='require'
        )
        print("✅ Connected to database")
        return conn
    except psycopg2.OperationalError as e:
        print(f"❌ Failed to connect to database: {str(e)}")
        print("\nNote: Supabase may not be reachable from your network.")
        print("This could be due to IPv6 connectivity issues or firewall restrictions.")
        sys.exit(1)

def hash_password(password: str) -> str:
    """Hash password using bcrypt (mimicking the backend)"""
    # For seeding, we'll use a pre-hashed password
    # In production, use proper bcrypt
    # This is: bcrypt.hashpw(b"password", bcrypt.gensalt()).decode()
    # Hashes for: 'doctorpass', 'password123', 'password123', 'password123'
    from passlib.context import CryptContext
    pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
    return pwd_context.hash(password)

def seed_database():
    """Seed the database with sample data"""
    conn = get_connection()
    cur = conn.cursor()
    
    try:
        print("\n" + "="*60)
        print("📊 Seeding Database with Sample Data")
        print("="*60)
        
        # Hashes for common test passwords
        doctor_pass_hash = hash_password("doctorpass")
        patient_pass_hash = hash_password("password123")
        
        # 1. Create doctor account
        print("\n1️⃣  Creating doctor account...")
        doctor_email = "doctor@example.com"
        cur.execute(
            """
            INSERT INTO "users" (email, "hashedPassword", role)
            VALUES (%s, %s, 'doctor')
            ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role
            RETURNING id;
            """,
            (doctor_email, doctor_pass_hash)
        )
        doctor_id = cur.fetchone()[0]
        print(f"   ✅ Doctor created (ID: {doctor_id})")
        print(f"   Email: {doctor_email}")
        print(f"   Password: doctorpass")
        
        # 2. Create patient accounts
        print("\n2️⃣  Creating patient accounts...")
        patients = [
            ("john.doe@example.com", "John Doe"),
            ("jane.smith@example.com", "Jane Smith"),
            ("alex.johnson@example.com", "Alex Johnson"),
        ]
        
        patient_ids = []
        for email, name in patients:
            cur.execute(
                """
                INSERT INTO "users" (email, "hashedPassword", role)
                VALUES (%s, %s, 'patient')
                ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role
                RETURNING id;
                """,
                (email, patient_pass_hash)
            )
            patient_id = cur.fetchone()[0]
            patient_ids.append(patient_id)
            print(f"   ✅ Patient created (ID: {patient_id}): {name}")
        
        # 3. Create medical documents
        print("\n3️⃣  Creating sample medical documents...")
        documents = [
            {
                "patient_id": patient_ids[0],
                "file_path": "uploads/john_doe_xray.pdf",
                "analysis": {
                    "ocr_result": "X-Ray showing normal chest cavity. No abnormalities detected.",
                    "nlp_result": "Normal radiographic findings. Recommend routine follow-up.",
                    "cv_result": "Image quality: Good. No regions of concern identified."
                }
            },
            {
                "patient_id": patient_ids[0],
                "file_path": "uploads/john_doe_bloodwork.pdf",
                "analysis": {
                    "ocr_result": "Complete Blood Count: WBC 7.2, RBC 4.8, Hemoglobin 14.5",
                    "nlp_result": "All values within normal range. Patient in good health.",
                    "cv_result": "Graph shows normal distribution. No anomalies."
                }
            },
            {
                "patient_id": patient_ids[1],
                "file_path": "uploads/jane_smith_ct.pdf",
                "analysis": {
                    "ocr_result": "CT Scan: Liver appears normal, no lesions detected.",
                    "nlp_result": "Abdominal imaging shows normal anatomy. Follow up as clinically indicated.",
                    "cv_result": "Scan quality excellent. No areas of concern."
                }
            },
            {
                "patient_id": patient_ids[1],
                "file_path": "uploads/jane_smith_cardio.pdf",
                "analysis": {
                    "ocr_result": "Echocardiogram: EF 55%, normal valve function.",
                    "nlp_result": "Cardiac function within normal limits. Continue current regimen.",
                    "cv_result": "Heart chambers properly sized. No structural abnormalities."
                }
            },
            {
                "patient_id": patient_ids[2],
                "file_path": "uploads/alex_johnson_mri.pdf",
                "analysis": {
                    "ocr_result": "Brain MRI: Normal brain parenchyma, no signal abnormalities.",
                    "nlp_result": "Neuroradiology assessment: Normal study. No acute findings.",
                    "cv_result": "White matter and gray matter normal. Ventricles appropriate size."
                }
            },
            {
                "patient_id": patient_ids[2],
                "file_path": "uploads/alex_johnson_labs.pdf",
                "analysis": {
                    "ocr_result": "Metabolic panel: Glucose 95, Creatinine 0.9, TSH 2.1",
                    "nlp_result": "Laboratory values all normal. Continue current care plan.",
                    "cv_result": "Values plotted show normal physiological ranges."
                }
            },
        ]
        
        for doc in documents:
            cur.execute(
                """
                INSERT INTO "medical_documents" ("patientId", "filePath", "aiAnalysisJson")
                VALUES (%s, %s, %s);
                """,
                (
                    doc["patient_id"],
                    doc["file_path"],
                    json.dumps(doc["analysis"])
                )
            )
            print(f"   ✅ Document created: {doc['file_path']}")
        
        conn.commit()
        
        print("\n" + "="*60)
        print("✅ Database Seeding Complete!")
        print("="*60)
        print("\n📋 Test Credentials:")
        print("\n  Doctor Account:")
        print(f"    Email: doctor@example.com")
        print(f"    Password: doctorpass")
        print("\n  Patient Accounts:")
        for email, name in patients:
            print(f"    Email: {email} ({name})")
            print(f"    Password: password123")
        
        print("\n🚀 You can now:")
        print("  1. Start the backend: python -m uvicorn backend.main:app --reload")
        print("  2. Start the frontend: npm start (from frontend directory)")
        print("  3. Login with any of the above credentials")
        
    except Exception as e:
        print(f"❌ Error during seeding: {str(e)}")
        conn.rollback()
        sys.exit(1)
    finally:
        cur.close()
        conn.close()

if __name__ == "__main__":
    # Check if psycopg2 is installed
    try:
        import psycopg2
    except ImportError:
        print("❌ psycopg2 is not installed")
        print("Install it with: pip install psycopg2-binary")
        sys.exit(1)
    
    try:
        import passlib
    except ImportError:
        print("❌ passlib is not installed")
        print("Install it with: pip install passlib")
        sys.exit(1)
    
    seed_database()
