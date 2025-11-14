#!/bin/bash
# Quick Start Guide for IntelliMed AI with Prisma

echo "
╔════════════════════════════════════════════════════════════════╗
║           IntelliMed AI - Prisma Migration Status             ║
╚════════════════════════════════════════════════════════════════╝

📋 OVERVIEW
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your IntelliMed AI project is fully prepared for Prisma ORM.
All code and configuration is ready—just need database access.

Current Status:
  ✅ Backend: Ready
  ✅ Frontend: Ready  
  ✅ Prisma Schema: Defined
  ✅ Database Utilities: Created
  ✅ Seed Scripts: Prepared
  ❌ Network Access: Blocked (DNS resolution issue)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🚀 QUICK START (Choose One)

Option 1: Use Local PostgreSQL (RECOMMENDED - Fastest)
────────────────────────────────────────────────────────

  # Install PostgreSQL
  sudo apt-get update
  sudo apt-get install postgresql postgresql-contrib

  # Create database
  sudo -u postgres psql
  > CREATE DATABASE intellimed_db;
  > CREATE USER intellimed_user WITH PASSWORD 'secure_password';
  > ALTER ROLE intellimed_user SET timezone TO 'UTC';
  > GRANT ALL PRIVILEGES ON DATABASE intellimed_db TO intellimed_user;
  > \\q

  # Update .env in project root
  DATABASE_URL=\"postgresql://intellimed_user:secure_password@localhost:5432/intellimed_db\"

  # Run migrations
  npx prisma migrate deploy

  # Seed test data
  python seed_data_prisma.py

  # Start backend
  source venv/bin/activate
  python -m uvicorn backend.main:app --reload

  # Start frontend (new terminal)
  cd frontend && npm start


Option 2: Use Railway.app (Cloud Alternative)
────────────────────────────────────────────────────────

  # 1. Sign up: https://railway.app
  # 2. Create new PostgreSQL service
  # 3. Copy connection string
  # 4. Update .env file with Railway DATABASE_URL
  # 5. Run: npx prisma migrate deploy
  # 6. Run: python seed_data_prisma.py


Option 3: Use Neon.tech (Cloud Alternative)
────────────────────────────────────────────────────────

  # 1. Sign up: https://neon.tech
  # 2. Create new database
  # 3. Copy connection string
  # 4. Update .env file
  # 5. Run migrations and seed


Option 4: Fix Supabase Access
────────────────────────────────────────────────────────

  # Try these diagnostics
  nslookup db.jwsivwgbepmmqztnmnpk.supabase.co
  
  # If DNS fails, your ISP/network is blocking it
  # Contact your ISP or network administrator
  # Or switch to local PostgreSQL (Option 1)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📁 KEY FILES

New Files Created:
  • backend/prisma_utils.py      - Prisma database operations
  • prisma/schema.prisma          - Database schema definition
  • seed_data_prisma.py           - Test data population
  • init_db_prisma.py             - Database initialization
  • verify_setup.py               - Setup verification tool
  • README_PRISMA.md              - Complete documentation

Documentation:
  • PRISMA_SETUP.md               - Detailed Prisma guide
  • MIGRATION_GUIDE.md            - SQLAlchemy → Prisma reference

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

✅ VERIFICATION

Check your setup status:

  python verify_setup.py

This will show:
  • Environment variables
  • Network connectivity
  • Prisma installation
  • Backend files
  • Frontend setup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔐 TEST CREDENTIALS

After seeding, use these to login:

  Admin Account:
    Email: admin@intellimed.ai
    Password: adminpassword

  Doctor Account:
    Email: doctor@example.com
    Password: doctorpass

  Patient Accounts:
    Email: john.doe@example.com
    Email: jane.smith@example.com
    Email: alex.johnson@example.com
    Password: password123 (all patients)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🛠️ DEVELOPMENT WORKFLOW

Once database is set up:

  1. Start PostgreSQL:
     sudo systemctl start postgresql

  2. Terminal 1 - Backend:
     cd /home/sarthak/IntelliMed-AI
     source venv/bin/activate
     python -m uvicorn backend.main:app --reload

  3. Terminal 2 - Frontend:
     cd /home/sarthak/IntelliMed-AI/frontend
     npm start

  4. Terminal 3 - Optional (Prisma Studio GUI):
     cd /home/sarthak/IntelliMed-AI
     npx prisma studio

  5. Open browser:
     http://localhost:3000

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📚 USEFUL COMMANDS

Prisma:
  npx prisma migrate deploy        # Run pending migrations
  npx prisma generate             # Generate Prisma client
  npx prisma validate             # Check schema validity
  npx prisma studio               # Open GUI database browser
  npx prisma db push              # Push schema to database
  npx prisma migrate reset         # Reset database (⚠️ deletes data)

Python:
  python verify_setup.py           # Check setup status
  python seed_data_prisma.py      # Populate test data
  python init_db_prisma.py        # Initialize database

Backend:
  python -m uvicorn backend.main:app --reload    # Dev server
  python -m uvicorn backend.main:app              # Production

Frontend:
  npm start                        # Dev server (port 3000)
  npm run build                    # Production build
  npm test                         # Run tests

Database:
  psql postgresql://...            # Connect directly
  \\dt                             # List tables
  \\d users                        # Describe table
  SELECT * FROM \"users\";          # Query data

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

❓ TROUBLESHOOTING

Problem: 'Cannot reach database server'
Solution: Use local PostgreSQL (Option 1) instead of Supabase

Problem: 'psycopg2.OperationalError'
Solution: Check .env DATABASE_URL is correct and database is running

Problem: Prisma schema not found
Solution: Make sure you're in project root directory

Problem: npm/node not found
Solution: Install Node.js from https://nodejs.org/

Problem: Python venv not activated
Solution: Run: source /home/sarthak/IntelliMed-AI/venv/bin/activate

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

📖 MORE INFORMATION

Read these files for detailed information:
  • README_PRISMA.md       - Complete migration summary
  • PRISMA_SETUP.md        - Detailed Prisma documentation
  • MIGRATION_GUIDE.md     - SQLAlchemy to Prisma reference
  • README.md              - Project overview

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎯 NEXT STEPS

1. Choose a database solution (see QUICK START above)
2. Set up the database
3. Run migrations: npx prisma migrate deploy
4. Populate test data: python seed_data_prisma.py
5. Start backend and frontend
6. Test with provided credentials
7. Read PRISMA_SETUP.md for API reference

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Happy coding! 🚀

Questions? See the documentation files or check:
  • Prisma: https://www.prisma.io/docs/
  • PostgreSQL: https://www.postgresql.org/docs/
  • FastAPI: https://fastapi.tiangolo.com/

"
