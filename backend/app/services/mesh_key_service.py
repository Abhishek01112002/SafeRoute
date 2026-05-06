import base64
import hashlib
import hmac
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.database import TouristMeshKey


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def derive_mesh_secret(tourist_id: str, tuid: str, key_version: int) -> str:
    """Derive the mobile mesh secret without storing raw secret material."""
    material = f"{tourist_id}:{tuid}:{key_version}".encode("utf-8")
    digest = hmac.new(
        settings.MESH_SECRET_MASTER_KEY.encode("utf-8"),
        material,
        hashlib.sha256,
    ).digest()
    return _b64url(digest)


def tuid_suffix(tuid: str) -> str:
    return (tuid or "")[-4:].upper()


async def ensure_active_mesh_key(db: AsyncSession, tourist_id: str, tuid: str) -> dict:
    result = await db.execute(
        select(TouristMeshKey)
        .where(TouristMeshKey.tourist_id == tourist_id, TouristMeshKey.status == "ACTIVE")
        .order_by(TouristMeshKey.key_version.desc())
        .limit(1)
    )
    key = result.scalar_one_or_none()

    if key is None:
        max_version = await db.scalar(
            select(func.max(TouristMeshKey.key_version)).where(TouristMeshKey.tourist_id == tourist_id)
        )
        key = TouristMeshKey(
            tourist_id=tourist_id,
            tuid=tuid,
            tuid_suffix=tuid_suffix(tuid),
            key_version=(max_version or 0) + 1,
            status="ACTIVE",
        )
        db.add(key)
        await db.flush()

    return {
        "mesh_secret": derive_mesh_secret(tourist_id, tuid, key.key_version),
        "mesh_key_version": key.key_version,
        "mesh_key_expires_at": None,
    }


async def rotate_mesh_key(db: AsyncSession, tourist_id: str, tuid: str) -> dict:
    now = datetime.now()
    grace_expires = now + timedelta(days=settings.MESH_KEY_GRACE_DAYS)
    active = (
        await db.execute(
            select(TouristMeshKey).where(
                TouristMeshKey.tourist_id == tourist_id,
                TouristMeshKey.status == "ACTIVE",
            )
        )
    ).scalars().all()
    for key in active:
        key.status = "GRACE"
        key.grace_expires_at = grace_expires

    max_version = await db.scalar(
        select(func.max(TouristMeshKey.key_version)).where(TouristMeshKey.tourist_id == tourist_id)
    )
    new_key = TouristMeshKey(
        tourist_id=tourist_id,
        tuid=tuid,
        tuid_suffix=tuid_suffix(tuid),
        key_version=(max_version or 0) + 1,
        status="ACTIVE",
    )
    db.add(new_key)
    await db.flush()
    return {
        "mesh_secret": derive_mesh_secret(tourist_id, tuid, new_key.key_version),
        "mesh_key_version": new_key.key_version,
        "mesh_key_expires_at": None,
    }


async def get_valid_key_for_suffix(
    db: AsyncSession,
    origin_tuid_suffix: str,
    key_version: int,
) -> Optional[TouristMeshKey]:
    now = datetime.now()
    result = await db.execute(
        select(TouristMeshKey).where(
            TouristMeshKey.tuid_suffix == origin_tuid_suffix.upper(),
            TouristMeshKey.key_version == key_version,
            TouristMeshKey.status.in_(["ACTIVE", "GRACE"]),
        )
    )
    for key in result.scalars().all():
        if key.status == "GRACE" and key.grace_expires_at and key.grace_expires_at < now:
            continue
        if key.revoked_at is not None:
            continue
        return key
    return None


async def get_valid_keys_for_suffix(
    db: AsyncSession,
    origin_tuid_suffix: str,
    key_version: int,
) -> list[TouristMeshKey]:
    now = datetime.now()
    result = await db.execute(
        select(TouristMeshKey).where(
            TouristMeshKey.tuid_suffix == origin_tuid_suffix.upper(),
            TouristMeshKey.key_version == key_version,
            TouristMeshKey.status.in_(["ACTIVE", "GRACE"]),
        )
    )
    keys: list[TouristMeshKey] = []
    for key in result.scalars().all():
        if key.status == "GRACE" and key.grace_expires_at and key.grace_expires_at < now:
            continue
        if key.revoked_at is not None:
            continue
        keys.append(key)
    return keys


def canonical_relay_payload(
    *,
    idempotency_hash_hex: str,
    tuid_suffix_value: str,
    latitude: float,
    longitude: float,
    unix_minute: int,
    trigger_type: str,
) -> str:
    return (
        f"v1:{idempotency_hash_hex.lower()}:{tuid_suffix_value.upper()}:"
        f"{latitude:.6f}:{longitude:.6f}:{unix_minute}:{trigger_type.upper()}"
    )


def truncated_hmac_hex(secret: str, canonical_payload: str, bytes_len: int = 4) -> str:
    digest = hmac.new(secret.encode("utf-8"), canonical_payload.encode("utf-8"), hashlib.sha256).digest()
    return digest[:bytes_len].hex()


def verify_relay_signature(secret: str, canonical_payload: str, signature_hex: str) -> bool:
    if not signature_hex or len(signature_hex) < 8:
        return False
    expected = truncated_hmac_hex(secret, canonical_payload, bytes_len=len(signature_hex) // 2)
    return hmac.compare_digest(expected.lower(), signature_hex.lower())
