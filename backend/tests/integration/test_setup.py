#!/usr/bin/env python3
"""
SafeRoute API - Automated Setup & Test Execution Script
FAANG Engineering Standards - All-in-One Setup Tool
"""

import os
import sys
import subprocess
import json
import time
import platform
from pathlib import Path
from datetime import datetime

class SetupManager:
    """Manages environment setup and test execution."""

    def __init__(self):
        self.backend_path = Path(__file__).resolve().parents[2]
        self.project_root = self.backend_path.parent
        self.venv_path = self.backend_path / "venv"
        self.env_file = self.backend_path / ".env"
        self.python_exe = self._get_python_exe()

    def _get_python_exe(self):
        """Get Python executable path."""
        if platform.system() == "Windows":
            return self.venv_path / "Scripts" / "python.exe"
        else:
            return self.venv_path / "bin" / "python"

    def print_header(self, title):
        """Print formatted header."""
        print("\n" + "=" * 80)
        print(f"  {title}")
        print("=" * 80 + "\n")

    def print_step(self, step_num, title):
        """Print formatted step."""
        print(f"\n{'─' * 80}")
        print(f"📍 STEP {step_num}: {title}")
        print(f"{'─' * 80}\n")

    def run_command(self, cmd, cwd=None, check=True):
        """Execute shell command with error handling."""
        try:
            result = subprocess.run(
                cmd,
                cwd=cwd or self.backend_path,
                shell=True,
                capture_output=True,
                text=True,
                check=False
            )
            if check and result.returncode != 0:
                print(f"❌ Command failed: {cmd}")
                print(f"Error: {result.stderr}")
                return False
            return result
        except Exception as e:
            print(f"❌ Error running command: {e}")
            return False

    def setup_virtual_environment(self):
        """Setup Python virtual environment."""
        self.print_step(1, "Setting Up Python Virtual Environment")

        if self.venv_path.exists():
            print(f"✅ Virtual environment already exists at {self.venv_path}")
            return True

        print(f"📦 Creating virtual environment...")
        result = self.run_command(f"python -m venv venv", cwd=self.backend_path)

        if result and result.returncode == 0:
            print(f"✅ Virtual environment created successfully")
            return True
        return False

    def install_dependencies(self):
        """Install Python dependencies."""
        self.print_step(2, "Installing Dependencies")

        req_file = self.backend_path / "requirements.txt"
        if not req_file.exists():
            print(f"❌ requirements.txt not found at {req_file}")
            return False

        print(f"📦 Installing packages from requirements.txt...")
        if platform.system() == "Windows":
            pip_cmd = str(self.venv_path / "Scripts" / "pip")
        else:
            pip_cmd = str(self.venv_path / "bin" / "pip")

        result = self.run_command(f"{pip_cmd} install -r requirements.txt",
                                 cwd=self.backend_path)

        if result and result.returncode == 0:
            print(f"✅ Dependencies installed successfully")
            return True
        return False

    def create_env_file(self):
        """Create .env file with default configuration."""
        self.print_step(3, "Creating Environment Configuration")

        env_content = """# SafeRoute Backend Environment Configuration
# Generated: {timestamp}

# Environment: development, staging, production
ENVIRONMENT=development

# Database Configuration
DATABASE_URL=sqlite:///./saferoute.db
ENABLE_PG=False
ENABLE_DUAL_WRITE=False
READ_FROM_PG=False

# Server Configuration
PORT=8000
HOST=0.0.0.0
RELOAD=True

# JWT Configuration
JWT_SECRET=replace-with-64-hex-chars-from-python-secrets-token-hex-32
JWT_ACCESS_EXPIRY_MINUTES=30
JWT_REFRESH_EXPIRY_DAYS=7

# Rate Limiting
RATE_LIMIT_ENABLED=True

# Feature Flags
ENABLE_PHOTO_STORAGE=False
ENABLE_QR_GENERATION=True

# Logging
LOG_LEVEL=INFO

# CORS
ALLOWED_ORIGINS=http://localhost:3000,http://localhost:5173,http://localhost:5174

# Database Retention
PING_RETENTION_DAYS=7
SOS_RETENTION_DAYS=90

# Redis (optional)
REDIS_URL=redis://localhost:6379

# MinIO (optional)
MINIO_ENABLED=False
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
""".format(timestamp=datetime.now().isoformat())

        if self.env_file.exists():
            print(f"⚠️  .env file already exists at {self.env_file}")
            response = input("Overwrite? (y/n): ").strip().lower()
            if response != 'y':
                print("Keeping existing .env file")
                return True

        try:
            with open(self.env_file, 'w') as f:
                f.write(env_content)
            print(f"✅ .env file created at {self.env_file}")
            print("   ℹ️  Update this file with your actual credentials before production")
            return True
        except Exception as e:
            print(f"❌ Failed to create .env file: {e}")
            return False

    def run_migrations(self):
        """Run database migrations."""
        self.print_step(4, "Running Database Migrations")

        print("📊 Checking migration status...")

        # Alembic upgrade
        python_exe = str(self.python_exe) if self.venv_path.exists() else "python"
        result = self.run_command(
            f"{python_exe} -m alembic upgrade head",
            cwd=self.backend_path,
            check=False
        )

        if result and result.returncode == 0:
            print(f"✅ Migrations completed successfully")
            return True
        else:
            print(f"⚠️  Migration may have failed or no migrations needed")
            print(f"    Output: {result.stderr if result else 'N/A'}")
            return True  # Don't fail on migration issues

    def verify_installation(self):
        """Verify installation by checking imports."""
        self.print_step(5, "Verifying Installation")

        print("🔍 Checking Python packages...")

        python_exe = str(self.python_exe) if self.venv_path.exists() else "python"

        packages = ["fastapi", "uvicorn", "sqlalchemy", "pydantic", "jwt"]
        all_ok = True

        for pkg in packages:
            result = self.run_command(
                f"{python_exe} -c \"import {pkg}; print('{pkg} OK')\"",
                cwd=self.backend_path,
                check=False
            )
            if result and result.returncode == 0:
                print(f"   ✅ {pkg}: {result.stdout.strip()}")
            else:
                print(f"   ❌ {pkg}: Missing")
                all_ok = False

        if all_ok:
            print(f"\n✅ All required packages installed")
            return True
        else:
            print(f"\n⚠️  Some packages missing. Try reinstalling.")
            return False

    def generate_startup_scripts(self):
        """Generate convenience startup scripts."""
        self.print_step(6, "Generating Startup Scripts")

        # Windows batch script
        if platform.system() == "Windows":
            batch_content = """@echo off
REM SafeRoute Backend - Startup Script
REM Navigate to backend directory
cd /d "%~dp0"

REM Activate virtual environment
call venv\\Scripts\\activate.bat

REM Start the server
echo Starting SafeRoute Backend...
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

pause
"""
            batch_file = self.backend_path / "start_server.bat"
            try:
                with open(batch_file, 'w') as f:
                    f.write(batch_content)
                print(f"✅ Created: start_server.bat")
            except Exception as e:
                print(f"⚠️  Could not create batch file: {e}")

        # PowerShell script
        ps_content = """
# SafeRoute Backend - PowerShell Startup Script

Write-Host "Starting SafeRoute Backend..." -ForegroundColor Green

$BackendPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $BackendPath

# Activate virtual environment
& ".\\venv\\Scripts\\Activate.ps1"

# Start the server
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

        ps_file = self.backend_path / "start_server.ps1"
        try:
            with open(ps_file, 'w') as f:
                f.write(ps_content)
            print(f"✅ Created: start_server.ps1")
        except Exception as e:
            print(f"⚠️  Could not create PowerShell script: {e}")

        # Test script
        test_content = """#!/usr/bin/env python3
# Run comprehensive API tests

import subprocess
import sys
import platform

backend_path = '{backend_path}'

# Activate venv and run tests
if platform.system() == "Windows":
    subprocess.run([
        "python",
        "comprehensive_test_suite.py"
    ], cwd=backend_path)
else:
    subprocess.run([
        "python3",
        "comprehensive_test_suite.py"
    ], cwd=backend_path)
""".format(backend_path=str(self.backend_path))

        test_file = self.backend_path / "run_tests.py"
        try:
            with open(test_file, 'w') as f:
                f.write(test_content)
            print(f"✅ Created: run_tests.py")
        except Exception as e:
            print(f"⚠️  Could not create test script: {e}")

    def print_summary(self):
        """Print setup summary and next steps."""
        self.print_header("SETUP COMPLETE ✅")

        print("📋 NEXT STEPS:\n")

        print("1️⃣  START THE BACKEND SERVER:")
        if platform.system() == "Windows":
            print(f"   PowerShell:  .\\start_server.ps1")
            print(f"   CMD:         start_server.bat")
        else:
            print(f"   bash:        source venv/bin/activate && python -m uvicorn app.main:app --reload")
        print()

        print("2️⃣  WAIT FOR SERVER TO START:")
        print(f"   ✓ Watch for: 'Uvicorn running on http://0.0.0.0:8000'")
        print(f"   ✓ Application startup complete")
        print()

        print("3️⃣  RUN COMPREHENSIVE TESTS (in another terminal):")
        print(f"   python comprehensive_test_suite.py")
        print()

        print("4️⃣  VIEW TEST RESULTS:")
        print(f"   api_test_report.json")
        print()

        print("5️⃣  VIEW API DOCUMENTATION:")
        print(f"   http://localhost:8000/docs")
        print(f"   http://localhost:8000/redoc")
        print()

        print("📚 REFERENCE DOCUMENTS:")
        print(f"   ✓ COMPREHENSIVE_API_ANALYSIS.md - Line-by-line code analysis")
        print(f"   ✓ comprehensive_test_suite.py - Automated test suite")
        print()

        print("🔒 SECURITY REMINDERS:")
        print(f"   ✓ Review .env file and update secrets for production")
        print(f"   ✓ Enable HTTPS in production")
        print(f"   ✓ Use PostgreSQL instead of SQLite for production")
        print(f"   ✓ Configure proper Redis for distributed caching")
        print()

        print("📊 MONITORING:")
        print(f"   Health Check:     GET http://localhost:8000/health")
        print(f"   Readiness Probe:  GET http://localhost:8000/ready")
        print(f"   OpenAPI Schema:   GET http://localhost:8000/openapi.json")
        print()

    def run_setup(self):
        """Execute complete setup."""
        self.print_header("SAFEROUTE API - COMPREHENSIVE SETUP")

        steps = [
            ("Virtual Environment", self.setup_virtual_environment),
            ("Dependencies", self.install_dependencies),
            ("Environment Config", self.create_env_file),
            ("Database Migrations", self.run_migrations),
            ("Installation Verification", self.verify_installation),
            ("Startup Scripts", self.generate_startup_scripts),
        ]

        for step_name, step_func in steps:
            if not step_func():
                print(f"\n⚠️  Setup incomplete: {step_name} failed")
                response = input("Continue anyway? (y/n): ").strip().lower()
                if response != 'y':
                    return False

        self.print_summary()
        return True


def main():
    """Main entry point."""
    try:
        manager = SetupManager()
        success = manager.run_setup()
        sys.exit(0 if success else 1)
    except KeyboardInterrupt:
        print("\n⚠️  Setup interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
