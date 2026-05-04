# main.py
"""
SafeRoute API entry point.

Render starts the service with `uvicorn main:app`, so this module must expose
the FastAPI application at import time.
"""
import os
from app.main import app

import uvicorn

from app.main import app

if __name__ == "__main__":
    is_production = os.getenv("ENVIRONMENT") == "production"
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        reload=not is_production
    )
