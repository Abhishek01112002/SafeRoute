# app/main.py
"""
SafeRoute V3 production entry point.
"""
import asyncio
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.config import settings
from app.core import limiter
from app.logging_config import get_logger, setup_logging
from app.middleware_logging import RequestLoggingMiddleware
from app.routes import (
    auth,
    authority,
    dashboard,
    destinations,
    groups,
    health,
    identity,
    location,
    media,
    onboard,
    sos,
    tourist,
    websocket,
    wellknown,
    zones,
)
from app.routes.trips import router as trips_router


setup_logging()
log = get_logger("app")


async def _periodic_cleanup() -> None:
    """Periodically clean up old location pings."""
    from app.db.crud import cleanup_old_pings
    from app.db.session import AsyncSessionLocal

    while True:
        try:
            await asyncio.sleep(3600)
            async with AsyncSessionLocal() as db:
                await cleanup_old_pings(db)
                await db.commit()
                log.info("cleanup.location_pings.completed")
        except Exception as exc:
            log.error("cleanup.location_pings.failed", error=str(exc))


@asynccontextmanager
async def lifespan(app: FastAPI):
    try:
        log.info(
            "app.startup",
            version="3.1.0",
            environment=os.getenv("ENVIRONMENT", "development"),
        )
        settings.validate()

        # create_all is idempotent for the local/hackathon deploy path.
        from app.db.session import init_models
        await init_models()

        from app.db.sqlite_legacy import init_db, sync_from_db
        init_db()
        sync_from_db()

        app.state.cleanup_task = asyncio.create_task(_periodic_cleanup())
        log.info("app.startup.complete")
    except Exception as exc:
        log.error("app.startup.failed", error=str(exc))
        raise

    try:
        yield
    finally:
        log.info("app.shutdown")
        cleanup_task = getattr(app.state, "cleanup_task", None)
        if cleanup_task:
            cleanup_task.cancel()
            try:
                await cleanup_task
            except asyncio.CancelledError:
                pass

        from app.db.session import engine
        await engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(
        title="SafeRoute API",
        version="3.1.0",
        description="Production-grade backend for SafeRoute Emergency Response System",
        docs_url="/docs" if os.getenv("ENVIRONMENT") != "production" else None,
        redoc_url="/redoc" if os.getenv("ENVIRONMENT") != "production" else None,
        lifespan=lifespan,
    )

    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

    app.add_middleware(RequestLoggingMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.get_allowed_origins_list(),
        allow_credentials="*" not in settings.get_allowed_origins_list(),
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(health.router, tags=["Health"])
    app.include_router(auth.router, prefix="/auth", tags=["Auth"])
    app.include_router(tourist.router, prefix="/v3/tourist", tags=["Tourist V3"])
    app.include_router(location.router, prefix="/location", tags=["Location"])
    app.include_router(sos.router, prefix="/sos", tags=["SOS"])
    app.include_router(zones.router, prefix="/zones", tags=["Zones"])
    app.include_router(websocket.router, prefix="/rooms", tags=["WebSocket"])
    app.include_router(groups.router)
    app.include_router(identity.router, prefix="/identity", tags=["Identity"])
    app.include_router(media.router, prefix="/v3/media", tags=["Media V3"])
    app.include_router(authority.router, prefix="/authority", tags=["Authority"])
    app.include_router(wellknown.router, prefix="/.well-known", tags=["Well Known"])
    app.include_router(destinations.router, prefix="/destinations", tags=["Destinations"])
    app.include_router(onboard.router, prefix="/onboard", tags=["Onboard"])
    app.include_router(dashboard.router, prefix="/dashboard", tags=["Dashboard"])
    app.include_router(trips_router)

    return app


app = create_app()


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8001)
