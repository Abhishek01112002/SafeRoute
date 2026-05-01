# app/__init__.py
from fastapi import FastAPI

def create_app() -> FastAPI:
    """FastAPI application factory."""
    from fastapi.middleware.cors import CORSMiddleware
    from slowapi.errors import RateLimitExceeded
    from slowapi.middleware import SlowAPIMiddleware

    from app.config import settings
    settings.validate()
    
    from app.core import limiter
    from app.middleware import add_correlation_id, rate_limit_exceeded_handler
    from app.routes import health, auth, tourist, location, sos, zones, rooms, destinations, onboard, dashboard
    
    import asyncio
    from contextlib import asynccontextmanager

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        # Startup: initialize local tables and run periodic cleanup.
        from app.db.session import db_session_context, init_models
        from app.db.crud import cleanup_old_pings

        await init_models()
        
        async def run_periodic_cleanup():
            while True:
                try:
                    async with db_session_context() as db:
                        print("🧹 [Maintenance] Running daily location ping cleanup...")
                        await cleanup_old_pings(db)
                except Exception as e:
                    print(f"❌ [Maintenance] Cleanup failed: {e}")
                
                # Run once every 24 hours
                await asyncio.sleep(86400)

        cleanup_task = asyncio.create_task(run_periodic_cleanup())
        yield
        # Shutdown
        cleanup_task.cancel()

    app = FastAPI(
        title="SafeRoute API",
        version="2.0.0",
        description="Production-grade Safety Backend",
        lifespan=lifespan
    )

    # ---------------------------------------------------------------------------
    # Middleware & Security
    # ---------------------------------------------------------------------------
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)
    
    app.add_middleware(SlowAPIMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.get_allowed_origins_list(),
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # Correlation ID
    app.middleware("http")(add_correlation_id)

    # ---------------------------------------------------------------------------
    # Routes
    # ---------------------------------------------------------------------------
    app.include_router(health.router, tags=["Health"])
    app.include_router(auth.router, prefix="/auth", tags=["Auth"])
    app.include_router(tourist.router, prefix="/tourist", tags=["Tourist"])
    app.include_router(location.router, prefix="/location", tags=["Location"])
    app.include_router(sos.router, prefix="/sos", tags=["SOS"])
    app.include_router(zones.router, prefix="/zones", tags=["Zones"])
    app.include_router(rooms.router, prefix="/rooms", tags=["Group Tour"])
    app.include_router(destinations.router, prefix="/destinations", tags=["Destinations"])
    app.include_router(onboard.router, prefix="/onboard", tags=["QR Onboarding"])
    app.include_router(dashboard.router, prefix="/dashboard", tags=["Command Center"])

    return app
