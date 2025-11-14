"""
Migration Guide: From SQLAlchemy to Prisma ORM

This document outlines the step-by-step process to migrate from SQLAlchemy to Prisma.

## Current Status
- ✅ Prisma schema defined in prisma/schema.prisma
- ⚠️ Migration to Supabase pending (blocked by network connectivity)
- 🔄 Backend code still using SQLAlchemy

## Network Issue
Supabase is currently unreachable from this network environment. This appears to be
an IPv6/firewall-related issue. The solution will work once connectivity is restored.

## Steps to Complete Migration

### Phase 1: Database (Once Supabase is Accessible)
1. Run: `npx prisma migrate deploy`
   - This will create tables based on prisma/schema.prisma
2. Run: `python seed_data_prisma.py`
   - This will populate test data

### Phase 2: Backend Code Migration
After the database is ready, update the backend endpoints:

1. Create Prisma client utilities in backend/prisma_utils.py
2. Update backend/auth.py to use Prisma for user queries
3. Update backend/api/auth_router.py to use Prisma
4. Update backend/api/patient_router.py to use Prisma
5. Update backend/api/doctor_router.py to use Prisma
6. Remove or deprecate backend/database.py (SQLAlchemy)

### Phase 3: Testing
1. Test all login endpoints
2. Test file upload and document retrieval
3. Test doctor dashboard

## Prisma Query Reference

### User Queries

**Find user by email (replaces: db.query(models.User).filter(...).first())**
```python
# SQLAlchemy:
user = db.query(models.User).filter(models.User.email == email).first()

# Prisma SQL:
SELECT * FROM "users" WHERE email = $1;

# Implementation in Python (using psycopg2):
cur.execute('SELECT * FROM "users" WHERE email = %s', (email,))
user = cur.fetchone()
```

**Create user (replaces: db.add(), db.commit(), db.refresh())**
```python
# Prisma SQL:
INSERT INTO "users" (email, "hashedPassword", role) VALUES ($1, $2, $3)
RETURNING *;
```

**Get all patients (replaces: db.query(models.User).filter(models.User.role == "patient").all())**
```python
# Prisma SQL:
SELECT * FROM "users" WHERE role = 'patient';
```

### Medical Document Queries

**Create document (replaces: db.add(), db.commit())**
```python
# Prisma SQL:
INSERT INTO "medical_documents" ("patientId", "filePath", "aiAnalysisJson")
VALUES ($1, $2, $3)
RETURNING *;
```

**Get patient documents (replaces: db.query(models.MedicalDocument).filter(...).all())**
```python
# Prisma SQL:
SELECT * FROM "medical_documents" WHERE "patientId" = $1;
```

## Alternative: Use Prisma JavaScript Client

For optimal performance, consider using the Prisma JavaScript client via Node.js:

1. Create a small Node.js service that wraps Prisma
2. Call it from Python via HTTP or subprocess
3. This gives you full Prisma features

Example Node.js wrapper:
```javascript
// services/db.js
const { PrismaClient } = require("@prisma/client");
const prisma = new PrismaClient();

module.exports = { prisma };

// services/api.js
const express = require("express");
const { prisma } = require("./db");
const app = express();

app.get("/api/user/:email", async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { email: req.params.email }
  });
  res.json(user);
});
```

## Important Notes

1. **Table Names**: Prisma converts model names to snake_case
   - `User` → `"users"`
   - `MedicalDocument` → `"medical_documents"`

2. **Column Names**: Some columns are also converted
   - `hashed_password` → `"hashedPassword"`
   - `patient_id` → `"patientId"`
   - Check prisma/schema.prisma for exact mappings

3. **SQL Escaping**: Always use parameterized queries
   - Good: `cur.execute('... WHERE id = %s', (id,))`
   - Bad: `cur.execute(f'... WHERE id = {id}')`

4. **Connection Management**: Use connection pooling for production
   - Prisma Accelerate for edge deployments
   - pgBouncer for on-premise setups
"""

# Phase 1: Check Supabase connectivity
print(__doc__)
