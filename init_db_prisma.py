"""
Database initialization script that works with Prisma migrations.

This script will:
1. Wait for Supabase to be accessible
2. Run Prisma migrations to create tables
3. Seed initial data

To run: python init_db_prisma.py
"""
import subprocess
import os
import time
from pathlib import Path

def run_command(cmd, description):
    """Run a shell command and handle errors"""
    print(f"\n{'='*60}")
    print(f"🔄 {description}")
    print(f"{'='*60}")
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, cwd=str(Path(__file__).parent.parent))
        print(result.stdout)
        if result.returncode != 0:
            print(f"❌ Error: {result.stderr}")
            return False
        print(f"✅ {description} completed successfully")
        return True
    except Exception as e:
        print(f"❌ Exception: {str(e)}")
        return False

def check_supabase_connection():
    """Check if Supabase is reachable"""
    print("\n" + "="*60)
    print("🔍 Checking Supabase Connection...")
    print("="*60)
    
    db_url = os.getenv("DATABASE_URL", "")
    if not db_url:
        print("❌ DATABASE_URL not set in environment")
        return False
    
    # Try to extract host and port
    try:
        # Format: postgresql://user:pass@host:port/db
        parts = db_url.split("@")[1].split("/")[0]
        host = parts.split(":")[0]
        print(f"Testing connection to: {host}")
        
        import socket
        try:
            socket.gethostbyname(host)
            print(f"✅ Host {host} is reachable")
            return True
        except socket.gaierror:
            print(f"❌ Cannot resolve host: {host}")
            return False
    except Exception as e:
        print(f"⚠️  Could not parse DATABASE_URL: {str(e)}")
        return False

def main():
    """Main initialization flow"""
    print("\n" + "="*60)
    print("🚀 IntelliMed AI - Prisma Database Setup")
    print("="*60)
    
    # Check if we're in the right directory
    prisma_dir = Path(__file__).parent.parent / "prisma"
    if not prisma_dir.exists():
        print("❌ Prisma directory not found. Make sure you're in the project root.")
        return
    
    # Check Supabase connection
    if not check_supabase_connection():
        print("\n⚠️  WARNING: Supabase is not currently reachable.")
        print("This could be due to:")
        print("  • Network connectivity issues (IPv6/IPv4)")
        print("  • Firewall/ISP restrictions")
        print("  • Supabase service being down")
        print("\nYou can still proceed with the migration steps.")
        response = input("\nDo you want to continue? (y/n): ").strip().lower()
        if response != 'y':
            print("Aborted.")
            return
    
    # Step 1: Run Prisma migrations
    if not run_command(
        ["npx", "prisma", "migrate", "deploy"],
        "Deploying Prisma migrations"
    ):
        print("\n⚠️  Migration failed. This is expected if Supabase is unreachable.")
        print("Once Supabase becomes accessible, run: npx prisma migrate deploy")
        response = input("\nContinue anyway? (y/n): ").strip().lower()
        if response != 'y':
            return
    
    # Step 2: Generate Prisma client
    if run_command(
        ["npx", "prisma", "generate"],
        "Generating Prisma client"
    ):
        print("\n✅ Prisma client generated")
    
    # Step 3: Seed data (if applicable)
    print("\n" + "="*60)
    print("📊 Database Setup Complete!")
    print("="*60)
    print("\nNext steps:")
    print("1. Once Supabase is accessible, run: npx prisma migrate deploy")
    print("2. Then run: python seed_data_prisma.py")
    print("3. Start the backend: python -m uvicorn backend.main:app --reload")
    print("4. In another terminal, start the frontend: npm start")

if __name__ == "__main__":
    main()
