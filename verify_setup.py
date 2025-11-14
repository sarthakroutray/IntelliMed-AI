#!/usr/bin/env python3
"""
Test script to verify Prisma setup and identify network issues.

This script helps diagnose:
1. Environment variable configuration
2. Network connectivity to Supabase
3. Prisma schema validity
4. Backend setup readiness

Run: python verify_setup.py
"""
import os
import sys
import subprocess
import socket
import json
from pathlib import Path
from urllib.parse import urlparse
from dotenv import load_dotenv

def print_header(text):
    print(f"\n{'='*60}")
    print(f"🔍 {text}")
    print('='*60)

def print_success(text):
    print(f"✅ {text}")

def print_warning(text):
    print(f"⚠️  {text}")

def print_error(text):
    print(f"❌ {text}")

def check_environment():
    """Verify environment setup"""
    print_header("Environment Variables")
    
    # Load environment variables
    env_files = [
        Path(__file__).parent / ".env",
        Path(__file__).parent / "backend" / ".env",
    ]
    
    env_vars_found = {}
    for env_file in env_files:
        if env_file.exists():
            load_dotenv(env_file)
            print_success(f"Loaded: {env_file}")
            env_vars_found[str(env_file)] = True
    
    if not env_vars_found:
        print_warning("No .env files found")
    
    # Check required variables
    required_vars = {
        "DATABASE_URL": "Supabase PostgreSQL connection string",
        "GOOGLE_CLIENT_ID": "Google OAuth2 Client ID",
        "SECRET_KEY": "JWT Secret Key (optional, has default)"
    }
    
    print("\nRequired Variables:")
    for var, description in required_vars.items():
        value = os.getenv(var)
        if value:
            masked = value[:20] + "..." if len(value) > 20 else value
            print_success(f"{var}: {masked}")
        else:
            if var == "SECRET_KEY":
                print_warning(f"{var}: Not set (using default)")
            else:
                print_error(f"{var}: Not set")
    
    return bool(os.getenv("DATABASE_URL"))

def check_network():
    """Test network connectivity to Supabase"""
    print_header("Network Connectivity")
    
    db_url = os.getenv("DATABASE_URL")
    if not db_url:
        print_warning("DATABASE_URL not set, skipping network test")
        return False
    
    try:
        parsed = urlparse(db_url)
        host = parsed.hostname
        port = parsed.port or 5432
        
        print(f"Testing connection to: {host}:{port}")
        
        # Test DNS resolution
        print("\n1. DNS Resolution:")
        try:
            ip = socket.gethostbyname(host)
            print_success(f"   {host} resolves to {ip}")
        except socket.gaierror as e:
            print_error(f"   Cannot resolve {host}: {e}")
            return False
        
        # Test TCP connectivity
        print("\n2. TCP Connection:")
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((host, port))
            sock.close()
            
            if result == 0:
                print_success(f"   Successfully connected to {host}:{port}")
                return True
            else:
                print_error(f"   Connection refused or timed out (code: {result})")
                print("   Possible reasons:")
                print("   - Firewall blocking outbound connections")
                print("   - ISP restricting database access")
                print("   - Supabase service unavailable")
                return False
        except socket.timeout:
            print_error(f"   Connection timed out (5s)")
            return False
        except Exception as e:
            print_error(f"   Connection error: {e}")
            return False
            
    except Exception as e:
        print_error(f"Error parsing DATABASE_URL: {e}")
        return False

def check_prisma_setup():
    """Verify Prisma is properly installed"""
    print_header("Prisma Setup")
    
    # Check if node_modules exists
    node_modules = Path(__file__).parent / "node_modules"
    if node_modules.exists():
        print_success("node_modules directory exists")
    else:
        print_error("node_modules not found - run: npm install")
        return False
    
    # Check if prisma is installed
    prisma_pkg = node_modules / ".bin" / "prisma"
    if prisma_pkg.exists():
        print_success("Prisma CLI is installed")
    else:
        print_warning("Prisma CLI not found in node_modules")
    
    # Check if @prisma/client is installed
    client_pkg = node_modules / "@prisma" / "client"
    if client_pkg.exists():
        print_success("@prisma/client is installed")
    else:
        print_warning("@prisma/client not found")
    
    # Check schema.prisma
    schema = Path(__file__).parent / "prisma" / "schema.prisma"
    if schema.exists():
        print_success(f"Schema file exists: {schema}")
        with open(schema) as f:
            content = f.read()
            if "enum Role" in content:
                print_success("  - Role enum defined")
            if "model User" in content:
                print_success("  - User model defined")
            if "model MedicalDocument" in content:
                print_success("  - MedicalDocument model defined")
    else:
        print_error(f"Schema file not found: {schema}")
        return False
    
    return True

def check_backend_setup():
    """Verify backend is properly configured"""
    print_header("Backend Setup")
    
    # Check Python version
    print("1. Python Version:")
    try:
        result = subprocess.run(
            [sys.executable, "--version"],
            capture_output=True,
            text=True
        )
        print_success(f"   {result.stdout.strip()}")
    except Exception as e:
        print_error(f"   Failed to check Python version: {e}")
    
    # Check venv
    print("\n2. Virtual Environment:")
    venv_path = Path(__file__).parent / "venv"
    if venv_path.exists():
        print_success(f"Virtual environment exists: {venv_path}")
    else:
        print_warning(f"Virtual environment not found at {venv_path}")
    
    # Check backend files
    print("\n3. Backend Files:")
    required_files = {
        "backend/main.py": "FastAPI main app",
        "backend/auth.py": "Authentication module",
        "backend/models.py": "SQLAlchemy models",
        "backend/prisma_utils.py": "Prisma utilities",
        "backend/api/auth_router.py": "Auth router",
        "backend/api/patient_router.py": "Patient router",
        "backend/api/doctor_router.py": "Doctor router",
    }
    
    for file, description in required_files.items():
        path = Path(__file__).parent / file
        if path.exists():
            print_success(f"   {file} ({description})")
        else:
            print_error(f"   {file} not found")
    
    # Check requirements
    print("\n4. Python Dependencies:")
    req_file = Path(__file__).parent / "backend" / "requirements.txt"
    if req_file.exists():
        with open(req_file) as f:
            deps = [line.strip() for line in f if line.strip() and not line.startswith("#")]
        print_success(f"   requirements.txt found ({len(deps)} packages)")
        key_deps = ["fastapi", "uvicorn", "sqlalchemy", "psycopg2", "passlib", "python-jose"]
        for dep in key_deps:
            if any(dep in d for d in deps):
                print_success(f"   - {dep}")
            else:
                print_warning(f"   - {dep} (not found)")
    else:
        print_error("   requirements.txt not found")
    
    return True

def check_frontend_setup():
    """Verify frontend is properly configured"""
    print_header("Frontend Setup")
    
    # Check package.json
    pkg_json = Path(__file__).parent / "package.json"
    if pkg_json.exists():
        print_success("package.json exists")
        with open(pkg_json) as f:
            data = json.load(f)
            if "dependencies" in data:
                print_success(f"  - {len(data['dependencies'])} dependencies")
                if "react" in data["dependencies"]:
                    print_success("  - React is installed")
    else:
        print_error("package.json not found")
    
    # Check frontend directory
    frontend = Path(__file__).parent / "frontend"
    if frontend.exists():
        print_success(f"Frontend directory exists: {frontend}")
        if (frontend / ".env").exists():
            print_success("  - .env file configured")
    else:
        print_error("Frontend directory not found")

def suggest_next_steps(db_connected, prisma_ok, backend_ok):
    """Suggest next steps based on checks"""
    print_header("Next Steps")
    
    if db_connected:
        print("✅ All checks passed! You can proceed with:")
        print("\n1. Run Prisma migrations:")
        print("   npx prisma migrate deploy")
        print("\n2. Seed the database:")
        print("   python seed_data_prisma.py")
        print("\n3. Start the backend:")
        print("   python -m uvicorn backend.main:app --reload")
        print("\n4. Start the frontend (in another terminal):")
        print("   cd frontend && npm start")
    else:
        print("⚠️  Database connection issue detected")
        print("\nOptions:")
        print("\n1. Use local PostgreSQL for development:")
        print("   sudo apt-get install postgresql postgresql-contrib")
        print("   Update .env with local database URL")
        print("\n2. Check with network administrator:")
        print("   - Port 5432 might be blocked")
        print("   - IPv6 connectivity issue")
        print("\n3. Try alternative cloud database:")
        print("   - Railway.app")
        print("   - Neon.tech")
        print("   - Render.com")

def main():
    """Run all checks"""
    print("\n" + "="*60)
    print("🚀 IntelliMed AI - Setup Verification")
    print("="*60)
    
    # Run checks
    env_ok = check_environment()
    db_connected = check_network()
    prisma_ok = check_prisma_setup()
    backend_ok = check_backend_setup()
    check_frontend_setup()
    
    # Suggest next steps
    suggest_next_steps(db_connected, prisma_ok, backend_ok)
    
    print("\n" + "="*60)
    print("Summary")
    print("="*60)
    print(f"Environment: {'✅' if env_ok else '⚠️'}")
    print(f"Network: {'✅' if db_connected else '❌'}")
    print(f"Prisma Setup: {'✅' if prisma_ok else '⚠️'}")
    print(f"Backend: {'✅' if backend_ok else '⚠️'}")
    print("="*60 + "\n")

if __name__ == "__main__":
    main()
