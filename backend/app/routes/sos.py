# app/routes/sos.py
import datetime
from fastapi import APIRouter, Depends, Body, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_current_tourist, get_current_authority
from app.db import crud
from app.db.session import get_db
from app.services.sos_dispatch import dispatch_sos_alert
from app.core import limiter
from app.services import group_safety

from app.models.schemas import MeshSOSSync
from app.services.identity_service import verify_sos_signature
from app.logging_config import get_logger

router = APIRouter()
log = get_logger("sos")

@router.post(
    "/trigger",
    responses={
        429: {
            "description": "Rate limit exceeded",
            "content": {
                "application/json": {
                    "example": {"error": "Rate limit exceeded: 3 per 1 minute"}
                }
            }
        }
    }
)
@limiter.limit("3/minute")
async def trigger_sos(request: Request, payload: dict = Body(...), tourist_id: str = Depends(get_current_tourist), db: AsyncSession = Depends(get_db)):
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")
    trigger_type = payload.get("trigger_type", "MANUAL")
    group_id = payload.get("group_id")

    # Validate coordinates
    if latitude is None or longitude is None:
        raise HTTPException(status_code=400, detail="latitude and longitude are required")

    if not isinstance(latitude, (int, float)) or not isinstance(longitude, (int, float)):
        raise HTTPException(status_code=400, detail="latitude and longitude must be numbers")

    if not (-90 <= latitude <= 90):
        raise HTTPException(status_code=400, detail=f"Invalid latitude: {latitude}. Must be between -90 and +90")

    if not (-180 <= longitude <= 180):
        raise HTTPException(status_code=400, detail=f"Invalid longitude: {longitude}. Must be between -180 and +180")

    # Validate trigger type enum
    VALID_TRIGGER_TYPES = {"MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"}
    if trigger_type not in VALID_TRIGGER_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid trigger_type: {trigger_type}. Must be one of {VALID_TRIGGER_TYPES}",
        )

    cid = getattr(request.state, "correlation_id", "-")

    log.info(
        "sos.trigger.received",
        tourist_id=tourist_id,
        lat=latitude,
        lng=longitude,
        trigger_type=trigger_type,
    )

    tourist_data = await crud.get_tourist(db, tourist_id)
    if not tourist_data:
        from app.models.database import Tourist

        tourist = await db.get(Tourist, tourist_id)
        if not tourist:
            log.warning("sos.trigger.tourist_not_found", tourist_id=tourist_id)
            raise HTTPException(status_code=404, detail="Tourist not found")
        tourist_data = {
            "tourist_id": tourist.tourist_id,
            "tuid": tourist.tuid,
            "full_name": tourist.full_name,
            "emergency_contact_name": tourist.emergency_contact_name,
            "emergency_contact_phone": tourist.emergency_contact_phone,
        }

    tuid = tourist_data.get("tuid")

    # Preserve client timestamp instead of overriding
    client_timestamp = payload.get("timestamp")
    if client_timestamp:
        try:
            timestamp = datetime.datetime.fromisoformat(client_timestamp.replace("Z", "+00:00"))
        except Exception:
            timestamp = datetime.datetime.now()
    else:
        timestamp = datetime.datetime.now()

    # Timestamp freshness validation: reject stale/future timestamps (>10 minutes drift)
    now = datetime.datetime.now(timestamp.tzinfo) if timestamp.tzinfo else datetime.datetime.now()
    if abs((now - timestamp).total_seconds()) > 600:
        raise HTTPException(
            status_code=400,
            detail="timestamp is too old or too far in the future",
        )

    if group_id:
        group = await group_safety.assert_group_member(db, str(group_id), str(tourist_id))
        recent_group_sos = await crud.check_recent_group_sos(
            db,
            tourist_id=str(tourist_id),
            group_id=group.group_id,
            timestamp=timestamp,
        )
        if recent_group_sos:
            return {
                "status": "duplicate_group_sos_ignored",
                "tourist_id": tourist_id,
                "group_id": group.group_id,
                "existing_event_id": recent_group_sos.id,
            }
        group_id = group.group_id

    sos_event = await crud.create_sos_event(
        db,
        tourist_id=str(tourist_id),
        lat=float(latitude),
        lon=float(longitude),
        trigger_type=str(trigger_type),
        correlation_id=getattr(request.state, "correlation_id", None),
        tuid=tuid,
        timestamp=timestamp,
        group_id=group_id,
    )

    correlation_id = getattr(request.state, "correlation_id", None)
    event = {
        "tourist_id": str(tourist_id),
        "tuid": tuid,
        "tourist_name": tourist_data.get("full_name"),
        "emergency_contact_name": tourist_data.get("emergency_contact_name"),
        "emergency_contact_phone": tourist_data.get("emergency_contact_phone"),
        "latitude": float(latitude),
        "longitude": float(longitude),
        "trigger_type": str(trigger_type),
        "group_id": group_id,
        "timestamp": timestamp.isoformat(),
        "correlation_id": correlation_id,
    }
    dispatch = dispatch_sos_alert(event)
    sos_event.dispatch_status = dispatch.get("status", "unknown")

    log.info(
        "sos.trigger.dispatched",
        tourist_id=tourist_id,
        tuid=tuid,
        group_id=group_id,
        trigger_type=trigger_type,
        dispatch_status=dispatch.get("status"),
        lat=latitude,
        lng=longitude,
    )

    if group_id:
        await group_safety.record_group_event(
            db,
            group_ref=group_id,
            tourist_id=str(tourist_id),
            event_type="sos_triggered",
            payload={"sos_event_id": getattr(sos_event, "id", None), "trigger_type": trigger_type},
        )

    return {
        "status": "alert_dispatched" if dispatch.get("status") == "delivered" else "alert_recorded",
        "tourist_id": tourist_id,
        "group_id": group_id,
        "timestamp": event["timestamp"],
        "dispatch": dispatch,
    }

@router.get("/events")
async def get_sos_events(
    limit: int = 50,
    offset: int = 0,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Authority endpoint — list all SOS events with pagination."""
    return await crud.get_sos_events_paginated(db, limit=limit, offset=offset)

@router.post("/events/{event_id}/respond")
async def respond_to_sos(
    event_id: int,
    payload: dict = Body(...),
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Authority endpoint — respond to an SOS event."""
    from app.models.database import SOSEvent
    from sqlalchemy import select

    result = await db.execute(select(SOSEvent).where(SOSEvent.id == event_id))
    event = result.scalar_one_or_none()
    
    if not event:
        raise HTTPException(status_code=404, detail="SOS event not found")

    response_text = payload.get("response")
    if not response_text:
        raise HTTPException(status_code=400, detail="Response text is required")

    event.authority_response = response_text
    event.resolved_at = datetime.datetime.now()
    event.is_synced = True  # Mark as resolved/synced
    
    await db.commit()
    
    log.info("sos.event.responded", event_id=event_id, authority_id=authority_id)
    return {"status": "responded", "event_id": event_id}

@router.post(
    "/sync",
    responses={
        429: {
            "description": "Rate limit exceeded",
            "content": {
                "application/json": {
                    "example": {"error": "Rate limit exceeded: 10 per 1 minute"}
                }
            }
        }
    }
)
@limiter.limit("10/minute")
async def sync_mesh_sos(
    request: Request,
    payload: MeshSOSSync,
    db: AsyncSession = Depends(get_db)
):
    """
    Sync an SOS event received via BLE Mesh.
    Verifies the cryptographic signature against the tourist's TUID.
    """
    # 1. Find tourist by TUID suffix
    tourist = await crud.get_tourist_by_tuid_suffix(db, payload.tourist_id_suffix)
    if not tourist:
        raise HTTPException(status_code=404, detail="Tourist not found for this suffix")

    # 2. Reconstruct payload for signature verification
    # Format: "suffix:lat:lng:timestamp"
    # Note: Using fixed precision for floats to ensure deterministic bytes
    payload_str = f"{payload.tourist_id_suffix}:{payload.latitude:.6f}:{payload.longitude:.6f}:{payload.timestamp.isoformat()}"
    payload_bytes = payload_str.encode()

    # 3. Verify signature
    if not verify_sos_signature(tourist.tuid, payload_bytes, payload.signature):
        raise HTTPException(status_code=401, detail="Invalid cryptographic signature for SOS packet")

    # 4. Check for de-duplication (don't record same SOS multiple times)
    # Deduplication logic: Same tourist, same location (approx), within 5 minutes
    existing = await crud.check_existing_sos(db, tourist.tourist_id, payload.latitude, payload.longitude, payload.timestamp)
    if existing:
        return {"status": "already_synced", "id": existing.id}

    group_id = None
    if payload.group_id:
        group = await group_safety.assert_group_member(db, payload.group_id, tourist.tourist_id)
        group_id = group.group_id
        recent_group_sos = await crud.check_recent_group_sos(
            db,
            tourist_id=tourist.tourist_id,
            group_id=group_id,
            timestamp=payload.timestamp,
        )
        if recent_group_sos:
            return {"status": "already_synced", "id": recent_group_sos.id, "group_id": group_id}

    # 5. Record SOS
    sos_event = await crud.create_sos_event(
        db,
        tourist_id=tourist.tourist_id,
        lat=payload.latitude,
        lon=payload.longitude,
        trigger_type="MESH_SYNC",
        tuid=tourist.tuid,
        timestamp=payload.timestamp,
        correlation_id=getattr(request.state, "correlation_id", None),
        group_id=group_id,
    )

    if group_id:
        await group_safety.record_group_event(
            db,
            group_ref=group_id,
            tourist_id=tourist.tourist_id,
            event_type="sos_relay",
            source="mesh",
            trust_level=group_safety.TRUST_MESH,
            payload={"sos_event_id": sos_event.id, "packet_id": payload.packet_id},
        )

    return {"status": "mesh_sos_recorded", "tuid": tourist.tuid, "group_id": group_id}
