# app/routes/health.py
import datetime
from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import text
from app.db.sqlite_legacy import tourists_db, authorities_db
from app.db.session import get_db
from app.config import settings
from app.services.redis_service import ping as redis_ping
from app.services.minio_service import minio_service

router = APIRouter()

# Simple in-memory metrics for Prometheus scraping
METRICS = {
    "request_count": 0,
    "error_count": 0,
    "qr_verification_failures": 0,
    "authority_scan_count": 0,
    "redis_hit_count": 0,
    "redis_miss_count": 0,
}

@router.get("/health")
async def health_check():
    """Basic health check with stats."""
    return {
        "status": "ok",
        "timestamp": datetime.datetime.now().isoformat() + "Z",
        "tourists": len(tourists_db),
        "authorities": len(authorities_db),
    }

@router.get("/live")
async def liveness_probe():
    """Simple liveness probe for container orchestration."""
    return {"status": "alive"}

@router.get("/ready")
async def readiness_probe(db: AsyncSession = Depends(get_db)):
    """
    Readiness probe for orchestration.
    Checks DB (Hard requirement), Redis (Soft), and MinIO (Soft).
    Returns 503 if DB is down, otherwise 200 (even if Redis/MinIO degraded).
    """
    checks = {
        "db": False,
        "redis": False,
        "minio": False,
    }

    # 1. DB Check
    try:
        await db.execute(text("SELECT 1"))
        checks["db"] = True
    except Exception as e:
        print(f"Readiness: DB check failed: {e}")

    # 2. Redis Check
    checks["redis"] = await redis_ping()

    # 3. MinIO Check
    checks["minio"] = minio_service.is_available

    # DB is the only hard requirement
    all_ok = checks["db"]
    status_code = 200 if all_ok else 503

    return JSONResponse(
        status_code=status_code,
        content={
            "status": "ready" if all_ok else "degraded",
            "checks": checks,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat()
        }
    )

@router.get("/metrics")
async def metrics():
    """Prometheus-compatible metrics endpoint."""
    output = []
    for key, value in METRICS.items():
        output.append(f"saferoute_{key} {value}")
    return "\n".join(output)

@router.post("/cleanup")
async def trigger_cleanup(db: AsyncSession = Depends(get_db)):
    """Manually trigger location ping retention cleanup."""
    from app.db.crud import cleanup_old_pings
    await cleanup_old_pings(db)
    return {"message": f"Cleanup triggered for retention: {settings.RETENTION_DAYS_LOCATION} days"}
