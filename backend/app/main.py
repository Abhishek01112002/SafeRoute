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
from app.routes.trips import router as trips_router
from app.core import limiter
from app.config import settings
from app.logging_config import setup_logging, get_logger
from app.middleware_logging import RequestLoggingMiddleware
from app.services.telemetry import telemetry
import asyncio
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

# Initialize logging
setup_logging()
log = get_logger("app")

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

    # Middleware — order matters: outermost runs first
    # RequestLoggingMiddleware wraps everything: logs every request + response
    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.get_allowed_origins_list(),
        allow_credentials="*" not in settings.get_allowed_origins_list(),
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
    app.include_router(trips_router)  # prefix is /v3/trips (defined in trips.py)

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
        try:
            log.info("app.startup", version="3.1.0", environment=os.getenv("ENVIRONMENT", "development"))
            settings.validate()

            # Use SQLAlchemy create_all (idempotent — skips existing tables/columns).
            # This replaces Alembic in the deploy pipeline; no migrations needed.
            from app.db.session import init_models
            await init_models()

            from app.db.sqlite_legacy import init_db, sync_from_db
            init_db()
            sync_from_db()

            # Start periodic cleanup task
            app.state.cleanup_task = asyncio.create_task(_periodic_cleanup())
            log.info("app.startup.complete")
        except Exception as exc:
            log.error("app.startup.failed", error=str(exc))
            raise  # Re-raise so uvicorn exits with a clear error

    @app.on_event("shutdown")
    async def shutdown_event():
        log.info("app.shutdown")

    return app

app = create_app()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
