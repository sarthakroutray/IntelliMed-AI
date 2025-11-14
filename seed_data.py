"""
Populate database with dummy patient data.
Run this script to add sample patients and medical documents.
"""
import sys
import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables
env_path = Path(__file__).parent / 'backend' / '.env'
if not env_path.exists():
    env_path = Path(__file__).parent / '.env'
load_dotenv(dotenv_path=env_path, override=True)

# Add the project root to the path
sys.path.insert(0, str(Path(__file__).parent))

# Create a fallback SQLite database for seeding when Supabase is unavailable
database_url = os.getenv("DATABASE_URL")
if not database_url or "supabase" in database_url:
    # Use SQLite for seeding
    os.environ["DATABASE_URL"] = "sqlite:///./intellimed_seed.db"
    print("⚠ Using SQLite for seeding (Supabase may be unreachable)")

from backend.database import Base, engine, SessionLocal
from backend import models, auth
from datetime import datetime, timedelta
import json

def seed_data():
    # Create tables
    Base.metadata.create_all(bind=engine)
    
    db = SessionLocal()
    try:
        # Clear existing data
        db.query(models.MedicalDocument).delete()
        db.query(models.User).delete()
        db.commit()
        print("✓ Cleared existing data")
        
        # Create dummy patients
        patients_data = [
            {
                "email": "john.doe@example.com",
                "password": "password123",
                "name": "John Doe",
                "role": models.Role.patient
            },
            {
                "email": "jane.smith@example.com",
                "password": "password123",
                "name": "Jane Smith",
                "role": models.Role.patient
            },
            {
                "email": "alex.johnson@example.com",
                "password": "password123",
                "name": "Alex Johnson",
                "role": models.Role.patient
            },
        ]
        
        # Create doctor user
        doctor = models.User(
            email="doctor@example.com",
            hashed_password=auth.get_password_hash("doctorpass"),
            role=models.Role.doctor
        )
        db.add(doctor)
        db.commit()
        print("✓ Created doctor user: doctor@example.com")
        
        # Create patient users
        patients = []
        for patient_data in patients_data:
            patient = models.User(
                email=patient_data["email"],
                hashed_password=auth.get_password_hash(patient_data["password"]),
                role=patient_data["role"]
            )
            db.add(patient)
            db.commit()
            patients.append(patient)
            print(f"✓ Created patient: {patient_data['email']}")
        
        # Create dummy medical documents for each patient
        sample_analyses = [
            {
                "diagnosis": "Hypertension",
                "confidence": 0.92,
                "recommendations": ["Monitor blood pressure daily", "Reduce sodium intake", "Exercise 30 mins daily"]
            },
            {
                "diagnosis": "Type 2 Diabetes",
                "confidence": 0.87,
                "recommendations": ["Regular glucose monitoring", "Dietary changes", "Exercise routine"]
            },
            {
                "diagnosis": "Asthma",
                "confidence": 0.95,
                "recommendations": ["Use inhaler as prescribed", "Avoid triggers", "Regular check-ups"]
            },
            {
                "diagnosis": "Hyperlipidemia",
                "confidence": 0.89,
                "recommendations": ["Reduce cholesterol intake", "Exercise regularly", "Monitor lipid levels"]
            },
            {
                "diagnosis": "COPD",
                "confidence": 0.91,
                "recommendations": ["Pulmonary function tests", "Bronchodilators", "Smoking cessation"]
            },
        ]
        
        for i, patient in enumerate(patients):
            for j in range(2):
                doc = models.MedicalDocument(
                    patient_id=patient.id,
                    file_path=f"/uploads/patient_{patient.id}_document_{j+1}.pdf",
                    upload_timestamp=datetime.utcnow() - timedelta(days=j),
                    ai_analysis_json=json.dumps(sample_analyses[(i*2 + j) % len(sample_analyses)])
                )
                db.add(doc)
        
        db.commit()
        print(f"✓ Created medical documents for {len(patients)} patients")
        print("\n" + "="*60)
        print("DUMMY DATA POPULATED SUCCESSFULLY!")
        print("="*60)
        print("\nTest Credentials:")
        print("-" * 60)
        print("Doctor Account:")
        print("  Email: doctor@example.com")
        print("  Password: doctorpass")
        print("\nPatient Accounts:")
        for patient_data in patients_data:
            print(f"  Email: {patient_data['email']}")
            print(f"  Password: password123")
        print("\nAdmin Account (hardcoded):")
        print("  Email: admin@intellimed.ai")
        print("  Password: adminpassword")
        print("="*60)
        
    except Exception as e:
        db.rollback()
        print(f"✗ Error: {str(e)}")
        raise
    finally:
        db.close()

if __name__ == "__main__":
    seed_data()
