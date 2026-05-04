# app/db/crud.py
from typing import List, Optional
from sqlalchemy import select, delete
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.models.database import Tourist, TouristDestination, Authority, SOSEvent, LocationPing, AuthorityScanLog, Destination, Zone
from app.models import schemas
from app.db import sqlite_legacy
from app.config import settings


def _tourist_to_dict(tourist: Tourist) -> dict:
    return {
        "tourist_id": tourist.tourist_id,
        "tuid": tourist.tuid or "",
        "full_name": tourist.full_name,
        "document_type": tourist.document_type,
        # document_number NOT returned — stored as hash only
        "photo_base64": tourist.photo_base64_legacy or "",
        "photo_object_key": tourist.photo_object_key or "",
        "document_object_key": tourist.document_object_key or "",
        "emergency_contact_name": tourist.emergency_contact_name,
        "emergency_contact_phone": tourist.emergency_contact_phone,
        "trip_start_date": tourist.trip_start_date.isoformat(),
        "trip_end_date": tourist.trip_end_date.isoformat(),
        "destination_state": tourist.destination_state,
        "date_of_birth": tourist.date_of_birth,
        "nationality": tourist.nationality,
        "migrated_from_legacy": tourist.migrated_from_legacy,
        "selected_destinations": [
            {
                "destination_id": dest.destination_id,
                "name": dest.name,
                "visit_date_from": dest.visit_date_from.isoformat(),
                "visit_date_to": dest.visit_date_to.isoformat(),
            }
            for dest in tourist.destinations
        ],
        "qr_data": tourist.qr_data,
        "created_at": tourist.created_at.isoformat() if tourist.created_at else datetime.now().isoformat(),
        "connectivity_level": tourist.connectivity_level,
        "offline_mode_required": tourist.offline_mode_required,
        "geo_fence_zones": [],
        "emergency_contacts": {},
        "risk_level": tourist.risk_level,
        "blood_group": tourist.blood_group or "Unknown",
        "is_synced": True,
    }


def _authority_to_dict(authority: Authority) -> dict:
    return {
        "authority_id": authority.authority_id,
        "full_name": authority.full_name,
        "designation": authority.designation,
        "department": authority.department,
        "badge_id": authority.badge_id,
        "jurisdiction_zone": authority.jurisdiction_zone,
        "phone": authority.phone,
        "email": authority.email,
        "password_hash": authority.password_hash,
        "status": authority.status,
        "role": authority.role,
        "created_at": authority.created_at.isoformat() if authority.created_at else datetime.now().isoformat(),
    }


def _destination_to_dict(dest: Destination) -> dict:
    return {
        "id": dest.id,
        "state": dest.state,
        "name": dest.name,
        "district": dest.district,
        "altitude_m": dest.altitude_m,
        "center_lat": dest.center_lat,
        "center_lng": dest.center_lng,
        "category": dest.category,
        "difficulty": dest.difficulty,
        "connectivity": dest.connectivity,
        "best_season": dest.best_season,
        "warnings_json": dest.warnings_json,
        "authority_id": dest.authority_id,
        "is_active": dest.is_active
    }


def _zone_to_dict(zone: Zone) -> dict:
    import json
    return {
        "id": zone.id,
        "destination_id": zone.destination_id,
        "authority_id": zone.authority_id,
        "name": zone.name,
        "type": zone.type,
        "shape": zone.shape,
        "center_lat": zone.center_lat,
        "center_lng": zone.center_lng,
        "radius_m": zone.radius_m,
        "polygon_points": json.loads(zone.polygon_json or "[]"),
        "is_active": zone.is_active,
        "created_at": zone.created_at.isoformat() if zone.created_at else None,
        "updated_at": zone.updated_at.isoformat() if zone.updated_at else None
    }

# ---------------------------------------------------------------------------
# Tourist CRUD
# ---------------------------------------------------------------------------

async def create_tourist(
    db: AsyncSession,
    tourist_in: schemas.TouristRegister,
    tourist_id: str,
    config: dict,
    tuid: Optional[str] = None,
    document_number_hash: Optional[str] = None,
    qr_jwt: Optional[str] = None,
) -> dict:
    """Create a tourist record in PG (and optionally dual-write to SQLite)."""
    legacy_qr = f"SAFEROUTE-{tourist_id}"

    new_tourist = Tourist(
        tourist_id=tourist_id,
        tuid=tuid,
        document_number_hash=document_number_hash,
        date_of_birth=tourist_in.date_of_birth or "1970-01-01",
        nationality=tourist_in.nationality or "IN",
        full_name=tourist_in.full_name,
        document_type=tourist_in.document_type,
        photo_base64_legacy=tourist_in.photo_base64,
        photo_object_key=tourist_in.photo_object_key,
        document_object_key=tourist_in.document_object_key,
        emergency_contact_name=tourist_in.emergency_contact_name,
        emergency_contact_phone=tourist_in.emergency_contact_phone,
        trip_start_date=_ensure_datetime(tourist_in.trip_start_date),
        trip_end_date=_ensure_datetime(tourist_in.trip_end_date),
        destination_state=tourist_in.destination_state,
        qr_data=qr_jwt or legacy_qr,
        connectivity_level=config.get("connectivity_level", "GOOD"),
        offline_mode_required=config.get("offline_mode_required", False),
        risk_level=config.get("risk_level", "LOW"),
        blood_group=tourist_in.blood_group,
    )

    # Add Destinations
    for dest in tourist_in.selected_destinations:
        new_tourist.destinations.append(TouristDestination(
            destination_id=dest.destination_id,
            name=dest.name,
            visit_date_from=_ensure_datetime(dest.visit_date_from),
            visit_date_to=_ensure_datetime(dest.visit_date_to),
        ))

    db.add(new_tourist)
    try:
        await db.flush()
    except Exception as e:
        import traceback
        # Sanitize data for logging (remove PII like document numbers)
        sanitized_input = tourist_in.model_dump(exclude={"document_number"})
        print(f"CRITICAL SQL ERROR in create_tourist: {e}")
        print(f"Sanitized Input: {sanitized_input}")
        print(f"Traceback: {traceback.format_exc()}")
        raise

    # Dual-write: keep legacy cache populated for SQLite/legacy clients
    legacy_data = {
        **tourist_in.model_dump(mode="json", exclude={"document_number"}),  # Never store raw doc number in cache
        "tourist_id": tourist_id,
        "tuid": tuid,
        "qr_data": qr_jwt or legacy_qr,
        "created_at": datetime.now().isoformat(),
        **config,
    }
    # Legacy cache persistence should never break the primary registration flow.
    try:
        sqlite_legacy.save_tourist(tourist_id, legacy_data)
    except Exception as e:
        print(f"⚠️ Legacy tourist cache write skipped for {tourist_id}: {e}")
    # Keep in-memory cache warm even if disk persistence fails.
    sqlite_legacy.tourists_db[tourist_id] = legacy_data

    return legacy_data


async def get_tourist(db: AsyncSession, tourist_id: str) -> Optional[dict]:
    """Get tourist by legacy tourist_id. Honors READ_FROM_PG."""
    if settings.READ_FROM_PG:
        try:
            result = await db.execute(
                select(Tourist)
                .options(selectinload(Tourist.destinations))
                .where(Tourist.tourist_id == tourist_id)
            )
            tourist = result.scalar_one_or_none()
            if tourist:
                return _tourist_to_dict(tourist)
        except Exception as e:
            print(f"CRITICAL: PG Read Failed for tourist {tourist_id}: {e}")
            if not settings.ENABLE_DUAL_WRITE:
                raise
            # Fall through to SQLite if dual-write is enabled

    # Check in-memory cache first (fast path)
    cached = sqlite_legacy.tourists_db.get(tourist_id)
    if cached:
        return cached

    # CRITICAL FIX: If not in cache, read from SQLite database file directly
    # This fixes the logout/login issue where tourists disappear after server restart
    try:
        from app.db.sqlite_legacy import load_tourists
        tourists = load_tourists()
        tourist_data = tourists.get(tourist_id)
        if tourist_data:
            # Warm the cache for next time
            sqlite_legacy.tourists_db[tourist_id] = tourist_data
            print(f"✅ Loaded tourist {tourist_id} from SQLite file (was not in cache)")
            return tourist_data
    except Exception as e:
        print(f"⚠️ SQLite file read failed for {tourist_id}: {e}")

    return None


async def get_tourists_paginated(db: AsyncSession, limit: int = 100, offset: int = 0) -> List[dict]:
    """List all registered tourists with pagination. Fetches from PG."""
    result = await db.execute(
        select(Tourist)
        .options(selectinload(Tourist.destinations))
        .order_by(Tourist.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    tourists = result.scalars().all()
    return [_tourist_to_dict(t) for t in tourists]


async def get_tourist_by_tuid(db: AsyncSession, tuid: str) -> Optional[dict]:
    """Get tourist by v3 TUID. Always queries PG."""
    try:
        result = await db.execute(
            select(Tourist)
            .options(selectinload(Tourist.destinations))
            .where(Tourist.tuid == tuid)
        )
        tourist = result.scalar_one_or_none()
        return _tourist_to_dict(tourist) if tourist else None
    except Exception as e:
        print(f"CRITICAL: PG TUID lookup failed for {tuid}: {e}")
        return None


async def get_tourist_by_doc_hash(db: AsyncSession, doc_hash: str) -> Optional[dict]:
    """
    Check if a document number hash is already registered.
    Used for duplicate prevention. Returns dict or None.
    """
    try:
        result = await db.execute(
            select(Tourist).where(Tourist.document_number_hash == doc_hash)
        )
        tourist = result.scalar_one_or_none()
        if not tourist:
            return None
        return {"tourist_id": tourist.tourist_id, "tuid": tourist.tuid}
    except Exception as e:
        print(f"ERROR: doc_hash lookup failed: {e}")
        return None


async def get_tourist_by_tuid_suffix(db: AsyncSession, suffix: str) -> Optional[Tourist]:
    """Find tourist by the end of their TUID (used for BLE Mesh Sync)."""
    try:
        result = await db.execute(
            select(Tourist).where(Tourist.tuid.like(f"%{suffix}"))
        )
        return result.scalar_one_or_none()
    except Exception as e:
        print(f"ERROR: TUID suffix lookup failed for {suffix}: {e}")
        return None


async def update_tourist_qr(db: AsyncSession, tourist_id: str, new_qr_jwt: str) -> None:
    """Update QR JWT for a tourist (used by refresh-qr endpoint)."""
    from sqlalchemy import update
    await db.execute(
        update(Tourist)
        .where(Tourist.tourist_id == tourist_id)
        .values(qr_data=new_qr_jwt)
    )
    # Update legacy cache
    if tourist_id in sqlite_legacy.tourists_db:
        sqlite_legacy.tourists_db[tourist_id]["qr_data"] = new_qr_jwt


# ---------------------------------------------------------------------------
# Authority CRUD
# ---------------------------------------------------------------------------

async def create_authority(db: AsyncSession, auth_in: schemas.AuthorityRegister, authority_id: str, hashed_pw: str) -> dict:
    new_auth = Authority(
        authority_id=authority_id,
        full_name=auth_in.full_name,
        designation=auth_in.designation,
        department=auth_in.department,
        badge_id=auth_in.badge_id,
        jurisdiction_zone=auth_in.jurisdiction_zone,
        phone=auth_in.phone,
        email=auth_in.email,
        password_hash=hashed_pw,
    )
    db.add(new_auth)
    await db.flush()

    legacy_data = {
        "authority_id": authority_id,
        "full_name": auth_in.full_name,
        "designation": auth_in.designation,
        "department": auth_in.department,
        "badge_id": auth_in.badge_id,
        "jurisdiction_zone": auth_in.jurisdiction_zone,
        "phone": auth_in.phone,
        "email": auth_in.email,
        "password": hashed_pw,
        "role": "authority",
        "status": "active",
    }
    try:
        sqlite_legacy.save_authority(authority_id, legacy_data)
    except Exception as e:
        print(f"⚠️ Legacy authority cache write skipped for {authority_id}: {e}")
    sqlite_legacy.authorities_db[authority_id] = legacy_data
    return legacy_data


async def get_authority(db: AsyncSession, authority_id: str) -> Optional[dict]:
    if settings.READ_FROM_PG:
        try:
            result = await db.execute(select(Authority).where(Authority.authority_id == authority_id))
            auth = result.scalar_one_or_none()
            return _authority_to_dict(auth) if auth else None
        except Exception as e:
            print(f"CRITICAL: PG Read Failed for authority {authority_id}: {e}")
            if not settings.ENABLE_DUAL_WRITE:
                raise
    return sqlite_legacy.authorities_db.get(authority_id)


async def get_authority_by_email(db: AsyncSession, email: str) -> Optional[dict]:
    if settings.READ_FROM_PG:
        try:
            result = await db.execute(select(Authority).where(Authority.email == email))
            auth = result.scalar_one_or_none()
            return _authority_to_dict(auth) if auth else None
        except Exception as e:
            print(f"CRITICAL: PG Read Failed for email {email}: {e}")
            if not settings.ENABLE_DUAL_WRITE:
                raise
    for _, data in sqlite_legacy.authorities_db.items():
        if data.get("email") == email:
            return data
    return None


# ---------------------------------------------------------------------------
# Destination & Zone CRUD
# ---------------------------------------------------------------------------

async def get_destinations(db: AsyncSession, state: Optional[str] = None) -> List[dict]:
    query = select(Destination)
    if state:
        query = query.where(Destination.state == state)
    result = await db.execute(query)
    return [_destination_to_dict(d) for d in result.scalars().all()]

async def get_states(db: AsyncSession) -> List[str]:
    from sqlalchemy import func as sqlfunc
    result = await db.execute(select(Destination.state).distinct().where(Destination.is_active == True))
    return sorted([r for r in result.scalars().all()])

async def create_destination(db: AsyncSession, dest_in: schemas.DestinationCreate, authority_id: str) -> dict:
    new_dest = Destination(
        id=dest_in.id,
        state=dest_in.state,
        name=dest_in.name,
        district=dest_in.district,
        altitude_m=dest_in.altitude_m,
        center_lat=dest_in.center_lat,
        center_lng=dest_in.center_lng,
        category=dest_in.category,
        difficulty=dest_in.difficulty,
        connectivity=dest_in.connectivity,
        best_season=dest_in.best_season,
        warnings_json=dest_in.warnings_json,
        authority_id=authority_id
    )
    db.add(new_dest)
    await db.flush()
    return _destination_to_dict(new_dest)

async def delete_destination(db: AsyncSession, dest_id: str, authority_id: str) -> bool:
    result = await db.execute(select(Destination).where(Destination.id == dest_id))
    dest = result.scalar_one_or_none()
    if dest:
        if dest.authority_id != authority_id:
            from fastapi import HTTPException
            raise HTTPException(status_code=403, detail="Jurisdiction mismatch")
        dest.is_active = False
        await db.flush()
        return True
    return False

async def create_zone(db: AsyncSession, zone_in: schemas.ZoneCreate, authority_id: str, zone_id: str) -> dict:
    import json
    new_zone = Zone(
        id=zone_id,
        destination_id=zone_in.destination_id,
        authority_id=authority_id,
        name=zone_in.name,
        type=zone_in.type.upper(),
        shape=zone_in.shape.upper(),
        center_lat=zone_in.center_lat,
        center_lng=zone_in.center_lng,
        radius_m=zone_in.radius_m,
        polygon_json=json.dumps([p.dict() for p in zone_in.polygon_points])
    )
    db.add(new_zone)
    await db.flush()
    return _zone_to_dict(new_zone)

async def get_zones(db: AsyncSession, destination_id: str) -> List[dict]:
    result = await db.execute(select(Zone).where(Zone.destination_id == destination_id, Zone.is_active == True))
    return [_zone_to_dict(z) for z in result.scalars().all()]

async def delete_zone(db: AsyncSession, zone_id: str, authority_id: str):
    result = await db.execute(select(Zone).where(Zone.id == zone_id))
    zone = result.scalar_one_or_none()
    if zone:
        if zone.authority_id != authority_id:
            from fastapi import HTTPException
            raise HTTPException(status_code=403, detail="Jurisdiction mismatch")
        zone.is_active = False
        await db.flush()

async def count_all_zones(db: AsyncSession) -> int:
    from sqlalchemy import func as sqlfunc
    result = await db.execute(select(sqlfunc.count()).where(Zone.is_active == True))
    return result.scalar() or 0

async def get_destination_by_id(db: AsyncSession, destination_id: str) -> Optional[dict]:
    result = await db.execute(select(Destination).where(Destination.id == destination_id))
    dest = result.scalar_one_or_none()
    return _destination_to_dict(dest) if dest else None

async def get_dashboard_metrics(db: AsyncSession) -> dict:
    """Aggregate metrics for the Command Center overview card."""
    from sqlalchemy import func as sqlfunc

    zone_count_result = await db.execute(
        select(sqlfunc.count()).select_from(Zone).where(Zone.is_active == True)
    )
    zone_count = zone_count_result.scalar() or 0

    # Tourist count from legacy SQLite (in-memory map is always current)
    tourist_count = len(sqlite_legacy.tourists_db)

    # SOS counts from legacy (persisted to SQLite)
    sos_events = sqlite_legacy.get_sos_events_legacy()
    active_sos = sum(1 for e in sos_events if e.get("is_synced") == 0)
    resolved_sos = sum(1 for e in sos_events if e.get("is_synced") == 1)

    return {
        "active_zones": zone_count,
        "registered_tourists": tourist_count,
        "active_sos": active_sos,
        "resolved_sos": resolved_sos,
    }

async def get_tourist_last_locations(limit: int = 200, offset: int = 0) -> list:
    """Return the most recent location ping for each tourist from the rolling deque with pagination."""
    seen = {}
    logs = list(sqlite_legacy.location_logs)
    # Iterate in reverse so we get the newest ping per tourist
    count = 0
    skipped = 0
    for ping in reversed(logs):
        tid = ping.get("tourist_id")
        if tid and tid not in seen:
            if skipped < offset:
                skipped += 1
                seen[tid] = None # placeholder to skip this tourist in next iterations
                continue

            seen[tid] = ping
            count += 1

        if count >= limit:
            break

    return [p for p in seen.values() if p is not None]

# ---------------------------------------------------------------------------
# Audit Scan Log
# ---------------------------------------------------------------------------

async def create_scan_log(
    db: AsyncSession,
    authority_id: str,
    scanned_tuid: str,
    tourist_id: Optional[str],
    ip_address: Optional[str],
    user_agent: Optional[str],
    photo_url_generated: bool = False,
) -> None:
    """Write a record to authority_scan_log for legal compliance."""
    import uuid
    log = AuthorityScanLog(
        id=str(uuid.uuid4()),
        authority_id=authority_id,
        scanned_tuid=scanned_tuid,
        tourist_id=tourist_id,
        ip_address=ip_address,
        user_agent=user_agent,
        photo_url_generated=photo_url_generated,
    )
    db.add(log)


# ---------------------------------------------------------------------------
# SOS & Location
# ---------------------------------------------------------------------------

async def create_sos_event(
    db: AsyncSession,
    tourist_id: str,
    lat: float,
    lon: float,
    trigger_type: str,
    correlation_id: Optional[str] = None,
    tuid: Optional[str] = None,
    timestamp: Optional[datetime] = None,
) -> None:
    new_event = SOSEvent(
        tourist_id=tourist_id,
        tuid=tuid,
        latitude=lat,
        longitude=lon,
        trigger_type=trigger_type,
        correlation_id=correlation_id,
        timestamp=timestamp,
    )
    db.add(new_event)
    sqlite_legacy.persist_sos(tourist_id, lat, lon, trigger_type)


async def check_existing_sos(
    db: AsyncSession,
    tourist_id: str,
    lat: float,
    lon: float,
    timestamp: datetime
) -> Optional[SOSEvent]:
    """Check if a similar SOS event already exists to prevent duplicates."""
    from datetime import timedelta
    # 5-minute window for same location (approx 100m)
    window_start = timestamp - timedelta(minutes=5)
    window_end = timestamp + timedelta(minutes=5)

    result = await db.execute(
        select(SOSEvent).where(
            SOSEvent.tourist_id == tourist_id,
            SOSEvent.latitude.between(lat - 0.001, lat + 0.001),
            SOSEvent.longitude.between(lon - 0.001, lon + 0.001),
            SOSEvent.timestamp.between(window_start, window_end)
        )
    )
    return result.scalar_one_or_none()


async def create_location_ping(db: AsyncSession, ping_in: schemas.LocationPing) -> None:
    new_ping = LocationPing(
        tourist_id=ping_in.tourist_id,
        tuid=ping_in.tuid,
        latitude=ping_in.latitude,
        longitude=ping_in.longitude,
        speed_kmh=ping_in.speed_kmh,
        accuracy_meters=ping_in.accuracy_meters,
        zone_status=ping_in.zone_status,
        timestamp=ping_in.timestamp or datetime.now(),
    )
    db.add(new_ping)


async def get_sos_events_for_tourist(db: AsyncSession, tourist_id: str, limit: int = 50, offset: int = 0) -> List[dict]:
    result = await db.execute(
        select(SOSEvent)
        .where(SOSEvent.tourist_id == tourist_id)
        .order_by(SOSEvent.timestamp.desc())
        .limit(limit)
        .offset(offset)
    )
    events = result.scalars().all()
    return [
        {
            "id": e.id,
            "tourist_id": e.tourist_id,
            "tuid": e.tuid,
            "latitude": e.latitude,
            "longitude": e.longitude,
            "trigger_type": e.trigger_type,
            "dispatch_status": e.dispatch_status,
            "timestamp": e.timestamp.isoformat(),
        }
        for e in events
    ]


async def get_sos_events_paginated(db: AsyncSession, limit: int = 50, offset: int = 0) -> List[dict]:
    """List all SOS events with pagination."""
    result = await db.execute(
        select(SOSEvent)
        .order_by(SOSEvent.timestamp.desc())
        .limit(limit)
        .offset(offset)
    )
    events = result.scalars().all()
    return [
        {
            "id": e.id,
            "tourist_id": e.tourist_id,
            "tuid": e.tuid,
            "latitude": e.latitude,
            "longitude": e.longitude,
            "trigger_type": e.trigger_type,
            "dispatch_status": e.dispatch_status,
            "status": "RESOLVED" if e.is_synced else "ACTIVE", # Logic mapping for dashboard
            "timestamp": e.timestamp.isoformat(),
        }
        for e in events
    ]


async def get_location_trail_for_tourist(db: AsyncSession, tourist_id: str, limit: int = 50) -> List[dict]:
    result = await db.execute(
        select(LocationPing)
        .where(LocationPing.tourist_id == tourist_id)
        .order_by(LocationPing.timestamp.desc())
        .limit(limit)
    )
    pings = result.scalars().all()
    return [
        {
            "latitude": p.latitude,
            "longitude": p.longitude,
            "speed_kmh": p.speed_kmh,
            "accuracy_meters": p.accuracy_meters,
            "zone_status": p.zone_status,
            "timestamp": p.timestamp.isoformat(),
        }
        for p in pings
    ]


# ---------------------------------------------------------------------------
# Authority Security & Login Tracking
# ---------------------------------------------------------------------------

async def get_authority_by_badge(db: AsyncSession, badge_id: str) -> Optional[dict]:
    """Get authority by badge ID."""
    if settings.ENABLE_PG:
        result = await db.execute(select(Authority).where(Authority.badge_id == badge_id))
        auth = result.scalar_one_or_none()
        if auth:
            return {
                "authority_id": auth.authority_id,
                "email": auth.email,
                "badge_id": auth.badge_id,
                "status": auth.status,
            }
    # Fallback to legacy
    return sqlite_legacy.get_authority_by_badge(badge_id)

async def increment_authority_failed_logins(db: AsyncSession, authority_id: str) -> None:
    """Increment failed login attempts for an authority."""
    if settings.ENABLE_PG:
        result = await db.execute(
            select(Authority).where(Authority.authority_id == authority_id)
        )
        auth = result.scalar_one_or_none()
        if auth:
            auth.failed_login_attempts = (auth.failed_login_attempts or 0) + 1
            await db.commit()
    else:
        sqlite_legacy.increment_failed_logins(authority_id)

async def reset_authority_failed_logins(db: AsyncSession, authority_id: str) -> None:
    """Reset failed login attempts after successful login."""
    if settings.ENABLE_PG:
        result = await db.execute(
            select(Authority).where(Authority.authority_id == authority_id)
        )
        auth = result.scalar_one_or_none()
        if auth:
            auth.failed_login_attempts = 0
            auth.last_login = datetime.now()
            await db.commit()
    else:
        sqlite_legacy.reset_failed_logins(authority_id)


# ---------------------------------------------------------------------------
# Maintenance & Retention
# ---------------------------------------------------------------------------

async def cleanup_old_pings(db: AsyncSession) -> None:
    """Delete location pings older than settings.RETENTION_DAYS_LOCATION."""
    from datetime import timedelta
    cutoff = datetime.now() - timedelta(days=settings.RETENTION_DAYS_LOCATION)
    if settings.ENABLE_PG:
        try:
            await db.execute(delete(LocationPing).where(LocationPing.timestamp < cutoff))
        except Exception as e:
            print(f"ERROR: PG Cleanup failed: {e}")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _ensure_datetime(value) -> datetime:
    """Accept datetime objects or ISO strings — always return datetime."""
    if isinstance(value, datetime):
        return value
    try:
        return datetime.fromisoformat(str(value).replace("Z", "+00:00"))
    except ValueError:
        return datetime.now()


# Backward compat alias
datetime_from_str = _ensure_datetime
