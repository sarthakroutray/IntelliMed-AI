# Prisma ORM Migration Guide

## Overview
This project is in the process of migrating from SQLAlchemy ORM to Prisma ORM for better type safety, performance, and developer experience.

## Current Status

### ✅ Completed
- [x] Prisma installation (`npm install -D prisma @prisma/client`)
- [x] Prisma schema definition (`prisma/schema.prisma`)
- [x] Database utilities for Prisma-style queries (`backend/prisma_utils.py`)
- [x] Seed data script for Prisma (`seed_data_prisma.py`)
- [x] Migration initialization script (`init_db_prisma.py`)

### ⚠️ Blocked (Network Issue)
- [ ] Prisma migration execution (`npx prisma migrate deploy`)
  - **Issue**: Supabase PostgreSQL is unreachable from this network
  - **Error**: P1001 - Can't reach database server at `db.jwsivwgbepmmqztnmnpk.supabase.co:5432`
  - **Cause**: Likely IPv6 connectivity or firewall restrictions
  - **Solution**: Once network issue is resolved, run the migration

### 🔄 Pending
- [ ] Update `backend/auth.py` to use Prisma utilities
- [ ] Update `backend/api/auth_router.py` to use Prisma
- [ ] Update `backend/api/patient_router.py` to use Prisma
- [ ] Update `backend/api/doctor_router.py` to use Prisma
- [ ] Remove or deprecate `backend/database.py` (SQLAlchemy)
- [ ] Test all endpoints with Prisma

## Files Created/Modified

### New Files
```
prisma/
├── schema.prisma          # Prisma schema (PostgreSQL provider)
└── migrations/            # Auto-generated migrations (empty until deploy)

backend/
├── prisma_utils.py        # Prisma utilities and raw SQL queries
└── prisma_client.py       # (Placeholder for future use)

/
├── init_db_prisma.py      # Database initialization script
├── seed_data_prisma.py    # Seed database with test data
├── MIGRATION_GUIDE.md     # Detailed migration reference
└── PRISMA_SETUP.md        # This file
```

### Existing Files (To Be Updated)
```
backend/
├── auth.py                # (Currently uses SQLAlchemy)
├── models.py              # (Currently SQLAlchemy models)
├── database.py            # (SQLAlchemy engine setup)
└── api/
    ├── auth_router.py     # (Currently uses SQLAlchemy)
    ├── patient_router.py  # (Currently uses SQLAlchemy)
    └── doctor_router.py   # (Currently uses SQLAlchemy)
```

## How to Use Prisma Utils

### Before (SQLAlchemy)
```python
from backend.database import get_db, Session
from sqlalchemy.orm import Session

def login(form_data, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(
        models.User.email == form_data.username
    ).first()
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return user
```

### After (Prisma Utils)
```python
from backend.prisma_utils import get_db

def login(form_data, db = Depends(get_db)):
    user = db.find_user_by_email(form_data.username)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    return user
```

## Key Differences

### Database Connection
- **SQLAlchemy**: Session-based, auto-commit with context manager
- **Prisma Utils**: Direct SQL queries, explicit commits per transaction

### User Queries
```python
# SQLAlchemy
user = db.query(models.User).filter(models.User.email == email).first()

# Prisma Utils
user = db.find_user_by_email(email)  # Returns dict or None
```

### Creating Records
```python
# SQLAlchemy
db_user = models.User(email=email, hashed_password=pwd_hash, role=role)
db.add(db_user)
db.commit()
db.refresh(db_user)
return db_user

# Prisma Utils
return db.create_user(email=email, hashed_password=pwd_hash, role=role)  # Returns dict
```

### Getting Related Data
```python
# SQLAlchemy
documents = user.documents  # Auto-loaded relationship

# Prisma Utils
documents = db.find_documents_by_patient(user['id'])  # Manual query
```

## Table and Column Mappings

The Prisma schema defines:

### User Model
```
Column            | SQLAlchemy Name      | Database Column
ID                | id                   | id
Email             | email                | email (UNIQUE)
Password          | hashed_password      | hashedPassword
Role              | role                 | role (ENUM)
Documents         | documents (relation) | N/A
```

### MedicalDocument Model
```
Column            | SQLAlchemy Name      | Database Column
ID                | id                   | id
Patient ID        | patient_id           | patientId (FK)
File Path         | file_path            | filePath
Upload Time       | upload_timestamp     | uploadTimestamp
Analysis JSON     | ai_analysis_json     | aiAnalysisJson
Patient (FK)      | patient (relation)   | patientId
```

## Network Connectivity Issue

The current blocker is that Supabase PostgreSQL cannot be reached from this network environment.

### Symptoms
- `npx prisma migrate dev` fails with error P1001
- Cannot connect to `db.jwsivwgbepmmqztnmnpk.supabase.co:5432`
- Backend server starts (doesn't require DB on startup)

### Root Cause
Likely one of:
1. IPv6 connectivity issue (ISP or firewall)
2. Outbound restriction on port 5432
3. Supabase region not accessible
4. Network routing issue

### Workarounds
1. **Use local PostgreSQL** for development:
   ```bash
   # Install PostgreSQL locally
   sudo apt-get install postgresql postgresql-contrib
   
   # Create local database
   sudo -u postgres createdb intellimed_db
   
   # Update .env
   DATABASE_URL="postgresql://postgres:password@localhost:5432/intellimed_db"
   ```

2. **Use different Supabase region** if available in your dashboard

3. **Use IPv4-only connection** if your ISP supports IPv6:
   ```bash
   # Test IPv4 connectivity
   curl -4 db.jwsivwgbepmmqztnmnpk.supabase.co
   ```

4. **Wait for network access** (check with network admin)

## Steps to Complete Migration (Once Network is Fixed)

### 1. Deploy Prisma Migrations
```bash
cd /home/sarthak/IntelliMed-AI
npx prisma migrate deploy
```

This will:
- Connect to Supabase
- Create tables: `users` and `medical_documents`
- Create enum type: `Role` (patient, doctor)

### 2. Seed Database
```bash
python seed_data_prisma.py
```

This will populate:
- 1 doctor account (doctor@example.com / doctorpass)
- 3 patient accounts (john.doe@example.com, jane.smith@example.com, alex.johnson@example.com / password123)
- 6 sample medical documents

### 3. Update Backend Code

Replace SQLAlchemy usage in:
- `backend/auth.py` - User lookups
- `backend/api/auth_router.py` - Login and registration
- `backend/api/patient_router.py` - Document upload
- `backend/api/doctor_router.py` - Patient and document queries

Example transformation:

**auth.py changes**:
```python
# OLD (SQLAlchemy)
from backend.database import get_db, Session
from sqlalchemy.orm import Session

def get_user(db: Session, email: str):
    return db.query(models.User).filter(models.User.email == email).first()

# NEW (Prisma Utils)
from backend.prisma_utils import get_db

def get_user(db, email: str):
    return db.find_user_by_email(email)
```

### 4. Test Application
```bash
# Terminal 1: Start backend
cd /home/sarthak/IntelliMed-AI
source venv/bin/activate
python -m uvicorn backend.main:app --reload

# Terminal 2: Start frontend
cd /home/sarthak/IntelliMed-AI/frontend
npm start

# Terminal 3: Test with curl
curl -X POST http://localhost:8000/api/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=doctor@example.com&password=doctorpass"
```

## Prisma Schema Reference

Located at: `prisma/schema.prisma`

```prisma
datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

generator client {
  provider = "prisma-client-py"
}

enum Role {
  patient
  doctor
}

model User {
  id                Int                @id @default(autoincrement())
  email             String             @unique
  hashedPassword    String
  role              Role
  documents         MedicalDocument[]
  
  @@map("users")
}

model MedicalDocument {
  id                Int       @id @default(autoincrement())
  patientId         Int
  filePath          String
  uploadTimestamp   DateTime  @default(now())
  aiAnalysisJson    Json?
  patient           User      @relation(fields: [patientId], references: [id])
  
  @@index([patientId])
  @@map("medical_documents")
}
```

## Troubleshooting

### Issue: `psycopg2.OperationalError: can't adapt type`
**Cause**: Direct SQL type mismatch  
**Solution**: Ensure data types match Prisma schema

### Issue: `DatabaseError: column "role" is not type boolean`
**Cause**: Role should be ENUM, not boolean  
**Solution**: Check `prisma/schema.prisma` - Role enum is correctly defined

### Issue: Connection pooling errors
**Cause**: Too many open connections  
**Solution**: Implement PgBouncer or Prisma Accelerate for production

## Next Steps

1. ✅ Resolve network connectivity to Supabase
2. ⏳ Run `npx prisma migrate deploy`
3. ⏳ Run `python seed_data_prisma.py`
4. ⏳ Update backend endpoints to use Prisma
5. ⏳ Test full application flow
6. ⏳ Deploy to production

## Questions?

Refer to:
- Prisma Documentation: https://www.prisma.io/docs/
- PostgreSQL Documentation: https://www.postgresql.org/docs/
- Supabase PostgreSQL: https://supabase.com/docs/guides/database
