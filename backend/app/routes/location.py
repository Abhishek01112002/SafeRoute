# app/routes/location.py
import datetime
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.schemas import LocationPing
from app.dependencies import get_current_tourist
from app.db import sqlite_legacy, crud
from app.db.session import get_db
from app.core import limiter

router = APIRouter()

@router.post(
    "/ping",
    responses={
        429: {
            "description": "Rate limit exceeded - maximum 30 pings per minute per tourist",
            "content": {
                "application/json": {
                    "example": {"error": "Rate limit exceeded: 30 per 1 minute"}
                }
            }
        }
    }
)
@limiter.limit("30/minute")
async def receive_ping(request: Request, ping: LocationPing, tourist_id: str = Depends(get_current_tourist), db: AsyncSession = Depends(get_db)):
    # JWT already validated by Depends, but verify it matches the ping
    if ping.tourist_id != tourist_id:
        raise HTTPException(status_code=403, detail="Tourist ID mismatch")

    # Coordinate validation
    if not (-90 <= ping.latitude <= 90):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid latitude: {ping.latitude}. Must be between -90 and +90",
        )
    if not (-180 <= ping.longitude <= 180):
        raise HTTPException(
            status_code=400,
            detail=f"Invalid longitude: {ping.longitude}. Must be between -180 and +180",
        )

    # Speed and accuracy validation
    if ping.speed_kmh is not None and ping.speed_kmh < 0:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid speed_kmh: {ping.speed_kmh}. Must be >= 0",
        )
    if ping.accuracy_meters is not None and ping.accuracy_meters < 0:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid accuracy_meters: {ping.accuracy_meters}. Must be >= 0",
        )

    # Timestamp freshness validation: reject stale/future timestamps (>10 minutes drift)
    if ping.timestamp is not None:
        now = datetime.datetime.now(ping.timestamp.tzinfo) if ping.timestamp.tzinfo else datetime.datetime.now()
        if abs((now - ping.timestamp).total_seconds()) > 600:
            raise HTTPException(
                status_code=400,
                detail="timestamp is too old or too far in the future",
            )

    # Validate tourist exists and fetch TUID
    tourist_data = await crud.get_tourist(db, tourist_id)
    if not tourist_data:
        raise HTTPException(status_code=404, detail="Tourist ID not registered")

    # Enrich ping with TUID
    ping.tuid = tourist_data.get("tuid")

    # deque automatically drops oldest entries
    sqlite_legacy.location_logs.append(ping.model_dump())

    # Save to PG
    await crud.create_location_ping(db, ping)
    return {"status": "received"}
