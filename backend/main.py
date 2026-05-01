# main.py
"""
SafeRoute API Entry Point
This file is a thin wrapper around the modular app package.
"""
import uvicorn
import os
from app import create_app

app = create_app()

if __name__ == "__main__":
    is_production = os.getenv("ENVIRONMENT") == "production"
    # In production, use a production-grade server like Gunicorn with Uvicorn workers
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=not is_production
    )
