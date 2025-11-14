"""
Initialize the SQLite database with tables.
Run this script once to set up the database.
"""
import os
import sys
from pathlib import Path

# Add the project root to the path
sys.path.insert(0, str(Path(__file__).parent))

from backend.database import Base, engine
from backend import models

# Create all tables
Base.metadata.create_all(bind=engine)
print("✓ Database tables created successfully!")
print(f"✓ SQLite database location: {os.path.abspath('intellimed.db')}")
