from typing import List, Optional
from sqlalchemy import select, update, delete
from datetime import datetime
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from app.models.database import Tourist, TouristDestination, Authority, SOSEvent, LocationPing
from app.models import schemas
from app.db import sqlite_legacy
from app.config import settings
from app.core import pwd_context


def _tourist_to_dict(tourist: Tourist) -> dict:
    return {
        "tourist_id": tourist.tourist_id,
        "full_name": tourist.full_name,
        "document_type": tourist.document_type,
        "document_number": tourist.document_number,
        "photo_base64": tourist.photo_base64_legacy or "",
        "emergency_contact_name": tourist.emergency_contact_name,
        "emergency_contact_phone": tourist.emergency_contact_phone,
        "trip_start_date": tourist.trip_start_date.isoformat(),
        "trip_end_date": tourist.trip_end_date.isoformat(),
        "destination_state": tourist.destination_state,
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
        "blockchain_hash": tourist.blockchain_hash,
        "connectivity_level": tourist.connectivity_level,
        "offline_mode_required": tourist.offline_mode_required,
        "geo_fence_zones": [],
        "emergency_contacts": {},
        "risk_level": tourist.risk_level,
        "blood_group": tourist.blood_group or "Unknown",
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

# ---------------------------------------------------------------------------
# Tourist CRUD
# ---------------------------------------------------------------------------

async def create_tourist(db: AsyncSession, tourist_in: schemas.TouristRegister, tourist_id: str, blockchain_hash: str, config: dict) -> dict:
    """Create a tourist record in PG (and optionally dual-write to SQLite)."""
    # 1. Prepare PG Model
    new_tourist = Tourist(
        tourist_id=tourist_id,
        full_name=tourist_in.full_name,
        document_type=tourist_in.document_type,
        document_number=tourist_in.document_number,
        photo_base64_legacy=tourist_in.photo_base64,
        emergency_contact_name=tourist_in.emergency_contact_name,
        emergency_contact_phone=tourist_in.emergency_contact_phone,
        trip_start_date=datetime_from_str(tourist_in.trip_start_date),
        trip_end_date=datetime_from_str(tourist_in.trip_end_date),
        destination_state=tourist_in.destination_state,
        qr_data=f"SAFEROUTE-{tourist_id}",
        blockchain_hash=blockchain_hash,
        connectivity_level=config.get("connectivity_level", "GOOD"),
        offline_mode_required=config.get("offline_mode_required", False),
        risk_level=config.get("risk_level", "LOW"),
        blood_group=getattr(tourist_in, "blood_group", None)
    )
    
    # Add Destinations
    for dest in tourist_in.selected_destinations:
        new_tourist.destinations.append(TouristDestination(
            destination_id=dest.destination_id,
            name=dest.name,
            visit_date_from=datetime_from_str(dest.visit_date_from),
            visit_date_to=datetime_from_str(dest.visit_date_to)
        ))

    db.add(new_tourist)
    await db.flush()
    
    # Keep the legacy cache populated because the Flutter client and the
    # default local mode still use this response shape.
    legacy_data = {
        **tourist_in.model_dump(),
        "tourist_id": tourist_id,
        "blockchain_hash": blockchain_hash,
        "qr_data": f"SAFEROUTE-{tourist_id}",
        "created_at": datetime.now().isoformat(),
        **config
    }
    sqlite_legacy.save_tourist(tourist_id, legacy_data)
    sqlite_legacy.tourists_db[tourist_id] = legacy_data

    return legacy_data

async def get_tourist(db: AsyncSession, tourist_id: str) -> Optional[dict]:
    """Get tourist record. Favors PG if READ_FROM_PG is enabled."""
    if settings.READ_FROM_PG:
        try:
            result = await db.execute(
                select(Tourist)
                .options(selectinload(Tourist.destinations))
                .where(Tourist.tourist_id == tourist_id)
            )
            tourist = result.scalar_one_or_none()
            return _tourist_to_dict(tourist) if tourist else None
        except Exception as e:
            # FAILOVER: If PG is down but we still have SQLite
            print(f"CRITICAL: PG Read Failed for tourist {tourist_id}: {e}")
            if not settings.ENABLE_DUAL_WRITE:
                raise
    
    return sqlite_legacy.tourists_db.get(tourist_id)

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
        password_hash=hashed_pw
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
        "status": "active"
    }
    sqlite_legacy.save_authority(authority_id, legacy_data)
    sqlite_legacy.authorities_db[authority_id] = legacy_data

    return legacy_data

async def get_authority(db: AsyncSession, authority_id: str) -> Optional[dict]:
    """Get authority by ID. Honors READ_FROM_PG."""
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
    """Get authority by email (used for login)."""
    if settings.READ_FROM_PG:
        try:
            result = await db.execute(select(Authority).where(Authority.email == email))
            auth = result.scalar_one_or_none()
            return _authority_to_dict(auth) if auth else None
        except Exception as e:
            print(f"CRITICAL: PG Read Failed for email {email}: {e}")
            if not settings.ENABLE_DUAL_WRITE:
                raise

    # Search in SQLite legacy
    for a_id, data in sqlite_legacy.authorities_db.items():
        if data.get("email") == email:
            return data
    return None

# ---------------------------------------------------------------------------
# SOS & Location Helpers
# ---------------------------------------------------------------------------

async def create_sos_event(db: AsyncSession, tourist_id: str, lat: float, lon: float, trigger_type: str, correlation_id: str = None):
    new_event = SOSEvent(
        tourist_id=tourist_id,
        latitude=lat,
        longitude=lon,
        trigger_type=trigger_type,
        correlation_id=correlation_id
    )
    db.add(new_event)

    sqlite_legacy.persist_sos(tourist_id, lat, lon, trigger_type)

async def create_location_ping(db: AsyncSession, ping_in: schemas.LocationPing):
    new_ping = LocationPing(
        tourist_id=ping_in.tourist_id,
        latitude=ping_in.latitude,
        longitude=ping_in.longitude,
        speed_kmh=ping_in.speed_kmh,
        accuracy_meters=ping_in.accuracy_meters,
        zone_status=ping_in.zone_status
    )
    db.add(new_ping)

# ---------------------------------------------------------------------------
# Maintenance & Retention
# ---------------------------------------------------------------------------

async def cleanup_old_pings(db: AsyncSession):
    """Delete location pings older than settings.RETENTION_DAYS_LOCATION."""
    from datetime import timedelta
    cutoff = datetime.now() - timedelta(days=settings.RETENTION_DAYS_LOCATION)
    
    # 1. Clean PG
    if settings.ENABLE_PG:
        try:
            await db.execute(delete(LocationPing).where(LocationPing.timestamp < cutoff))
            # Session commit happens in dependency
        except Exception as e:
            print(f"ERROR: PG Cleanup failed: {e}")

    # 2. Clean SQLite (Manual implementation if needed, but SQLite is typically ephemeral/local)
    # For now, PG is our primary focus for retention.

# Helper
def datetime_from_str(s: str) -> datetime:
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except ValueError:
        return datetime.now()
