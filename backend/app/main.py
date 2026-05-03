# app/main.py
"""
SafeRoute V3 - Production Entry Point
Modularized FastAPI application factory.
"""
import os
import time
import uuid
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware
from app.routes import (
    health, auth, tourist, location, sos, zones, websocket,
    identity, media, authority, wellknown, destinations, onboard, dashboard
)
from app.core import limiter
from app.config import settings
from app.logging_config import setup_logging
from app.services.telemetry import telemetry
import asyncio
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

# Initialize logging
setup_logging()

class CorrelationIdMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
        request.state.correlation_id = correlation_id
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response

def create_app() -> FastAPI:
    app = FastAPI(
        title="SafeRoute API",
        version="3.1.0",
        description="Production-grade backend for SafeRoute Emergency Response System",
        docs_url="/docs" if os.getenv("ENVIRONMENT") != "production" else None,
        redoc_url="/redoc" if os.getenv("ENVIRONMENT") != "production" else None,
    )

    # Rate Limiting
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    # Middleware
    app.add_middleware(CorrelationIdMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    # Routing
    app.include_router(health.router, tags=["Health"])
    app.include_router(auth.router, prefix="/auth", tags=["Auth"])
    app.include_router(tourist.router, prefix="/v3/tourist", tags=["Tourist V3"])
    app.include_router(location.router, prefix="/location", tags=["Location"])
    app.include_router(sos.router, prefix="/sos", tags=["SOS"])
    app.include_router(zones.router, prefix="/zones", tags=["Zones"])
    app.include_router(websocket.router, prefix="/rooms", tags=["WebSocket"])
    app.include_router(identity.router, prefix="/identity", tags=["Identity"])
    app.include_router(media.router, prefix="/v3/media", tags=["Media V3"])
    app.include_router(authority.router, prefix="/authority", tags=["Authority"])
    app.include_router(wellknown.router, prefix="/.well-known", tags=["Well Known"])
    app.include_router(destinations.router, prefix="/destinations", tags=["Destinations"])
    app.include_router(onboard.router, prefix="/onboard", tags=["Onboard"])
    app.include_router(dashboard.router, prefix="/dashboard", tags=["Dashboard"])

    # Background task for periodic cleanup
    _cleanup_task = None

    async def _periodic_cleanup():
        """Periodically clean up old location pings."""
        from app.db.session import AsyncSessionLocal
        from app.db.crud import cleanup_old_pings

        while True:
            try:
                await asyncio.sleep(3600)  # Run every hour
                async with AsyncSessionLocal() as db:
                    await cleanup_old_pings(db)
                    await db.commit()
                    print("🧹 Periodic cleanup: Old pings cleaned")
            except Exception as e:
                print(f"⚠️ Cleanup task error: {e}")

    @app.on_event("startup")
    async def startup_event():
        print(">>> SafeRoute V3 Backend Starting...")
        from app.db.sqlite_legacy import init_db, sync_from_db
        init_db()
        sync_from_db()

        # Start periodic cleanup task
        app.state.cleanup_task = asyncio.create_task(_periodic_cleanup())
        print("[CLEANUP] Periodic cleanup task started")

    @app.on_event("shutdown")
    async def shutdown_event():
        print("<<< SafeRoute V3 Backend Shutting Down...")

    return app

app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
