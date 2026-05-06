# app/routes/sos.py
import datetime
import hashlib
from fastapi import APIRouter, Depends, Body, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.dependencies import get_current_tourist, get_current_authority
from app.db import crud
from app.db.session import get_db
from app.core import limiter
from app.services import group_safety

from app.models.schemas import MeshSOSSync, SOSTriggerRequest, SOSRelayTriggerRequest
from app.services.identity_service import verify_sos_signature
from app.services.jwt_service import verify_jwt_payload
from app.services.mesh_key_service import (
    canonical_relay_payload,
    derive_mesh_secret,
    get_valid_keys_for_suffix,
    verify_relay_signature,
)
from app.services.sos_delivery import (
    INCIDENT_ACKNOWLEDGED,
    INCIDENT_RESOLVED,
    QUEUE_DELIVERED,
    create_or_get_queued_sos,
    get_status_payload,
    idempotency_from_compact_hash,
    write_audit,
)
from app.models.database import SOSEvent, SOSDeliveryAudit, SOSDispatchQueue
from app.logging_config import get_logger
from sqlalchemy import select

router = APIRouter()
log = get_logger("sos")

@router.post(
    "/trigger",
    status_code=202,
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
async def trigger_sos(
    request: Request,
    payload: SOSTriggerRequest,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    latitude = payload.latitude
    longitude = payload.longitude
    trigger_type = payload.trigger_type
    group_id = payload.group_id

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
    client_timestamp = payload.timestamp
    if client_timestamp:
        timestamp = client_timestamp
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

    idempotency_key = payload.idempotency_key or hashlib.sha256(
        f"{tourist_id}:{latitude:.6f}:{longitude:.6f}:{timestamp.isoformat()}:{trigger_type}".encode("utf-8")
    ).hexdigest()[:32]

    sos_event, queue, created = await create_or_get_queued_sos(
        db,
        tourist_id=str(tourist_id),
        tuid=tuid,
        latitude=float(latitude),
        longitude=float(longitude),
        trigger_type=str(trigger_type),
        timestamp=timestamp,
        idempotency_key=idempotency_key,
        source="DIRECT",
        group_id=group_id,
        correlation_id=getattr(request.state, "correlation_id", None),
    )

    log.info(
        "sos.trigger.queued",
        tourist_id=tourist_id,
        tuid=tuid,
        group_id=group_id,
        trigger_type=trigger_type,
        queue_id=queue.queue_id,
        delivery_state=queue.state,
        was_created=created,
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

    status = await get_status_payload(db, sos_event)
    return {
        "status": "queued",
        "tourist_id": tourist_id,
        "sos_id": sos_event.id,
        "queue_id": queue.queue_id,
        "group_id": group_id,
        "timestamp": timestamp.isoformat(),
        "delivery_state": queue.state,
        "status_url": f"/sos/{sos_event.id}/status",
        "message": status["message"],
    }


def _optional_relayer_tourist_id(request: Request) -> str | None:
    auth = request.headers.get("authorization") or request.headers.get("Authorization")
    if not auth or not auth.lower().startswith("bearer "):
        return None
    payload = verify_jwt_payload(auth.split(" ", 1)[1].strip())
    if payload and payload.get("role") == "tourist" and payload.get("type") != "refresh":
        return payload.get("sub") or payload.get("tourist_id")
    return None


@router.post("/trigger/relay", status_code=202)
async def trigger_relay_sos(
    request: Request,
    payload: SOSRelayTriggerRequest,
    db: AsyncSession = Depends(get_db),
):
    if not (-90 <= payload.latitude <= 90) or not (-180 <= payload.longitude <= 180):
        raise HTTPException(status_code=400, detail="Invalid coordinates")
    if payload.trigger_type not in {"MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"}:
        raise HTTPException(status_code=400, detail="Invalid trigger_type")
    if len(payload.origin_tuid_suffix.strip()) != 4:
        raise HTTPException(status_code=400, detail="origin_tuid_suffix must be 4 characters")
    if not payload.idempotency_hash or len(payload.idempotency_hash) < 12:
        raise HTTPException(status_code=400, detail="idempotency_hash must be at least 12 hex characters")

    packet_time = datetime.datetime.fromtimestamp(payload.unix_minute * 60)
    if abs((datetime.datetime.now() - packet_time).total_seconds()) > 1800:
        raise HTTPException(status_code=400, detail="relay packet timestamp is stale or too far in the future")

    keys = await get_valid_keys_for_suffix(
        db,
        payload.origin_tuid_suffix,
        payload.key_version,
    )
    if not keys:
        raise HTTPException(status_code=404, detail="No valid mesh key for origin suffix")

    canonical = canonical_relay_payload(
        idempotency_hash_hex=payload.idempotency_hash,
        tuid_suffix_value=payload.origin_tuid_suffix,
        latitude=payload.latitude,
        longitude=payload.longitude,
        unix_minute=payload.unix_minute,
        trigger_type=payload.trigger_type,
    )
    matched_key = None
    for key in keys:
        secret = derive_mesh_secret(key.tourist_id, key.tuid, key.key_version)
        if verify_relay_signature(secret, canonical, payload.origin_signature):
            matched_key = key
            break

    if matched_key is None:
        raise HTTPException(status_code=401, detail="Invalid origin signature")

    idempotency_key = idempotency_from_compact_hash(
        payload.origin_tuid_suffix,
        payload.idempotency_hash,
        payload.unix_minute,
    )
    relayer_tourist_id = _optional_relayer_tourist_id(request)
    sos_event, queue, created = await create_or_get_queued_sos(
        db,
        tourist_id=matched_key.tourist_id,
        tuid=matched_key.tuid,
        latitude=payload.latitude,
        longitude=payload.longitude,
        trigger_type=payload.trigger_type,
        timestamp=packet_time,
        idempotency_key=idempotency_key,
        source="BLE_RELAY",
        group_id=payload.group_id,
        relayed_by_tourist_id=relayer_tourist_id,
        correlation_id=getattr(request.state, "correlation_id", None),
    )
    await write_audit(
        db,
        sos_event_id=sos_event.id,
        queue_id=queue.queue_id,
        channel="BLE_RELAY",
        target=relayer_tourist_id,
        status="SUCCESS",
        provider_status="RELAY_ACCEPTED" if created else "DUPLICATE_RELAY",
        attempt_number=0,
    )
    status = await get_status_payload(db, sos_event)
    return {
        "status": "queued",
        "sos_id": sos_event.id,
        "queue_id": queue.queue_id,
        "origin_tourist_id": matched_key.tourist_id,
        "delivery_state": queue.state,
        "status_url": f"/sos/{sos_event.id}/status",
        "message": status["message"],
    }


@router.get("/{sos_id}/status")
async def get_sos_status(
    sos_id: int,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    event = await db.get(SOSEvent, sos_id)
    if not event:
        raise HTTPException(status_code=404, detail="SOS event not found")
    if event.tourist_id != tourist_id:
        raise HTTPException(status_code=403, detail="Cannot view another tourist's SOS")
    return await get_status_payload(db, event)

@router.get("/events")
async def get_sos_events(
    limit: int = 50,
    offset: int = 0,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Authority endpoint — list all SOS events with pagination."""
    return await crud.get_sos_events_paginated(db, limit=limit, offset=offset)


@router.get("/events/{event_id}/delivery")
async def get_sos_delivery_audit(
    event_id: int,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db),
):
    """Authority endpoint - inspect audited delivery attempts for one incident."""
    event = await db.get(SOSEvent, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="SOS event not found")

    queue = (
        await db.execute(
            select(SOSDispatchQueue)
            .where(SOSDispatchQueue.sos_event_id == event_id)
            .order_by(SOSDispatchQueue.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    audit_rows = (
        await db.execute(
            select(SOSDeliveryAudit)
            .where(SOSDeliveryAudit.sos_event_id == event_id)
            .order_by(SOSDeliveryAudit.timestamp.desc())
        )
    ).scalars().all()

    return {
        "event": await get_status_payload(db, event),
        "queue": {
            "queue_id": queue.queue_id if queue else None,
            "state": queue.state if queue else event.delivery_state,
            "attempt_count": queue.attempt_count if queue else 0,
            "last_error": queue.last_error if queue else None,
            "delivered_at": queue.delivered_at.isoformat() if queue and queue.delivered_at else None,
            "escalated_at": queue.escalated_at.isoformat() if queue and queue.escalated_at else None,
            "next_attempt_at": queue.next_attempt_at.isoformat() if queue and queue.next_attempt_at else None,
        },
        "audit": [
            {
                "audit_id": row.audit_id,
                "queue_id": row.queue_id,
                "channel": row.channel,
                "target": row.target,
                "status": row.status,
                "provider_status": row.provider_status,
                "error_message": row.error_message,
                "attempt_number": row.attempt_number,
                "timestamp": row.timestamp.isoformat() if row.timestamp else None,
            }
            for row in audit_rows
        ],
    }


@router.post("/events/{event_id}/acknowledge")
async def acknowledge_sos(
    event_id: int,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db),
):
    """Authority endpoint - human acknowledgement without resolving the incident."""
    event = await db.get(SOSEvent, event_id)
    if not event:
        raise HTTPException(status_code=404, detail="SOS event not found")
    if event.incident_status == INCIDENT_RESOLVED:
        return {"status": "already_resolved", "event_id": event_id}

    event.incident_status = INCIDENT_ACKNOWLEDGED
    event.acknowledged_at = event.acknowledged_at or datetime.datetime.now()
    event.acknowledged_by = authority_id
    event.dispatch_status = "acknowledged"

    queue = (
        await db.execute(
            select(SOSDispatchQueue)
            .where(SOSDispatchQueue.sos_event_id == event_id)
            .order_by(SOSDispatchQueue.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    await write_audit(
        db,
        sos_event_id=event.id,
        queue_id=queue.queue_id if queue else None,
        channel="AUTHORITY",
        target=authority_id,
        status="SUCCESS",
        provider_status="ACKNOWLEDGED",
        attempt_number=queue.attempt_count if queue else 0,
    )

    log.info("sos.event.acknowledged", event_id=event_id, authority_id=authority_id)
    return await get_status_payload(db, event)

@router.post("/events/{event_id}/respond")
async def respond_to_sos(
    event_id: int,
    payload: dict = Body(default_factory=dict),
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Authority endpoint — respond to an SOS event."""
    result = await db.execute(select(SOSEvent).where(SOSEvent.id == event_id))
    event = result.scalar_one_or_none()
    
    if not event:
        raise HTTPException(status_code=404, detail="SOS event not found")

    response_text = payload.get("response") or "Response initiated from command centre"
    event.authority_response = response_text
    event.acknowledged_at = event.acknowledged_at or datetime.datetime.now()
    event.acknowledged_by = event.acknowledged_by or authority_id
    event.resolved_at = datetime.datetime.now()
    event.incident_status = INCIDENT_RESOLVED
    event.delivery_state = QUEUE_DELIVERED if event.delivery_state in {"PENDING", "DISPATCHING"} else event.delivery_state
    event.dispatch_status = "resolved"
    event.is_synced = True  # Legacy dashboard compatibility

    queue = (
        await db.execute(
            select(SOSDispatchQueue)
            .where(SOSDispatchQueue.sos_event_id == event_id)
            .order_by(SOSDispatchQueue.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if queue and queue.state in {"PENDING", "DISPATCHING"}:
        queue.state = QUEUE_DELIVERED
        queue.delivered_at = queue.delivered_at or datetime.datetime.now()
        queue.next_attempt_at = None
    await write_audit(
        db,
        sos_event_id=event.id,
        queue_id=queue.queue_id if queue else None,
        channel="AUTHORITY",
        target=authority_id,
        status="SUCCESS",
        provider_status="RESOLVED",
        attempt_number=queue.attempt_count if queue else 0,
    )
    
    log.info("sos.event.responded", event_id=event_id, authority_id=authority_id)
    return {"status": "resolved", "event_id": event_id}

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

    # 5. Queue SOS through the same durable delivery path as direct and relay triggers.
    idempotency_key = payload.packet_id or hashlib.sha256(
        f"LEGACY_SYNC:{tourist.tourist_id}:{payload.latitude:.6f}:{payload.longitude:.6f}:{payload.timestamp.isoformat()}".encode("utf-8")
    ).hexdigest()[:32]
    sos_event, queue, created = await create_or_get_queued_sos(
        db,
        tourist_id=tourist.tourist_id,
        tuid=tourist.tuid,
        latitude=payload.latitude,
        longitude=payload.longitude,
        trigger_type="MESH_SYNC",
        timestamp=payload.timestamp,
        idempotency_key=idempotency_key,
        source="LEGACY_MESH_SYNC",
        group_id=group_id,
        correlation_id=getattr(request.state, "correlation_id", None),
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

    return {
        "status": "mesh_sos_recorded",
        "created": created,
        "id": sos_event.id,
        "queue_id": queue.queue_id,
        "tuid": tourist.tuid,
        "group_id": group_id,
    }
