# main.py
"""
SafeRoute API Entry Point
This file is a thin wrapper around the modular app package.
"""
import uvicorn
import os
from app.main import app

if __name__ == "__main__":
    is_production = os.getenv("ENVIRONMENT") == "production"
    # In production, use a production-grade server like Gunicorn with Uvicorn workers
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        reload=not is_production
    )
