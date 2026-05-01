# app/routes/sos.py
import datetime
from fastapi import APIRouter, Depends, Body, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_current_tourist, get_current_authority
from app.db import sqlite_legacy, crud
from app.db.session import get_db
from app.services.sos_dispatch import dispatch_sos_alert
from app.core import limiter

router = APIRouter()

@router.post("/trigger")
@limiter.limit("3/minute")
async def trigger_sos(request: Request, payload: dict = Body(...), tourist_id: str = Depends(get_current_tourist), db: AsyncSession = Depends(get_db)):
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")
    trigger_type = payload.get("trigger_type", "MANUAL")

    if latitude is None or longitude is None:
        raise HTTPException(status_code=400, detail="latitude and longitude are required")

    await crud.create_sos_event(
        db, 
        tourist_id=str(tourist_id), 
        lat=float(latitude), 
        lon=float(longitude), 
        trigger_type=str(trigger_type),
        correlation_id=getattr(request.state, "correlation_id", None)
    )

    tourist = sqlite_legacy.tourists_db.get(str(tourist_id), {})
    event = {
        "tourist_id": str(tourist_id),
        "tourist_name": tourist.get("full_name"),
        "emergency_contact_name": tourist.get("emergency_contact_name"),
        "emergency_contact_phone": tourist.get("emergency_contact_phone"),
        "latitude": float(latitude),
        "longitude": float(longitude),
        "trigger_type": str(trigger_type),
        "timestamp": datetime.datetime.now().isoformat(),
    }
    dispatch = dispatch_sos_alert(event)

    return {
        "status": "alert_dispatched" if dispatch.get("status") == "delivered" else "alert_recorded",
        "tourist_id": tourist_id,
        "timestamp": event["timestamp"],
        "dispatch": dispatch,
    }

@router.get("/events")
async def get_sos_events(authority_id: str = Depends(get_current_authority), db: AsyncSession = Depends(get_db)):
    """Authority endpoint — list all SOS events."""
    return sqlite_legacy.get_sos_events_legacy()
