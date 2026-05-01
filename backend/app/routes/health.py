# app/routes/health.py
import datetime
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.sqlite_legacy import tourists_db, authorities_db
from app.db.session import get_db
from app.config import settings

router = APIRouter()

@router.get("/health")
async def health_check():
    """Full health check with basic stats."""
    return {
        "status": "ok",
        "timestamp": datetime.datetime.now().isoformat(),
        "tourists": len(tourists_db),
        "authorities": len(authorities_db),
    }

@router.get("/live")
async def liveness_probe():
    """Simple liveness probe for container orchestration."""
    return {"status": "alive"}

@router.get("/ready")
async def readiness_probe():
    """Readiness probe - can be expanded to check DB connectivity."""
    return {"status": "ready"}

@router.post("/cleanup")
async def trigger_cleanup(db: AsyncSession = Depends(get_db)):
    """Manually trigger location ping retention cleanup."""
    from app.db.crud import cleanup_old_pings
    await cleanup_old_pings(db)
    return {"message": f"Cleanup triggered for retention: {settings.RETENTION_DAYS_LOCATION} days"}
