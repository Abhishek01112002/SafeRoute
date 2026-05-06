import datetime
import json
import random
import string
import time
from typing import Optional

from fastapi import HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.database import (
    Tourist,
    TouristGroup,
    TouristGroupEvent,
    TouristGroupLocationSnapshot,
    TouristGroupMember,
)


INVITE_CODE_LENGTH = 6
INVITE_TTL_HOURS = 24
MAX_GROUP_MEMBERS = 12
JOIN_FAILURE_LIMIT = 5
JOIN_FAILURE_WINDOW_SECONDS = 600
LOCATION_UPDATE_MIN_SECONDS = 5
STALE_SIGNAL_SECONDS = 60

SHARING = "SHARING"
PAUSED = "PAUSED"
ACTIVE = "ACTIVE"
CLOSED = "CLOSED"

SOURCE_WEBSOCKET = "websocket"
SOURCE_MESH = "mesh"
TRUST_CONFIRMED = "confirmed"
TRUST_MESH = "mesh_trusted"
TRUST_ADVISORY = "advisory"

_failed_join_attempts: dict[str, list[float]] = {}
_invite_alphabet = "".join(ch for ch in string.ascii_uppercase + string.digits if ch not in {"0", "O", "1", "I"})


def _now() -> datetime.datetime:
    return datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)


def _iso(value: Optional[datetime.datetime]) -> Optional[str]:
    return value.isoformat() if value else None


def _normalize_invite(value: str) -> str:
    return value.strip().upper().replace("-", "").replace(" ", "")


async def _get_tourist(db: AsyncSession, tourist_id: str) -> Tourist:
    tourist = await db.get(Tourist, tourist_id)
    if not tourist:
        raise HTTPException(status_code=404, detail="Tourist not found")
    return tourist


async def _generate_invite_code(db: AsyncSession) -> str:
    for _ in range(100):
        code = "".join(random.choice(_invite_alphabet) for _ in range(INVITE_CODE_LENGTH))
        exists = await db.scalar(select(func.count()).select_from(TouristGroup).where(TouristGroup.invite_code == code))
        if not exists:
            return code
    raise HTTPException(status_code=500, detail="Could not generate group invite code")


async def _log_event(
    db: AsyncSession,
    group_id: str,
    event_type: str,
    tourist_id: Optional[str] = None,
    source: str = "server",
    trust_level: str = TRUST_CONFIRMED,
    payload: Optional[dict] = None,
) -> None:
    db.add(
        TouristGroupEvent(
            group_id=group_id,
            tourist_id=tourist_id,
            event_type=event_type,
            source=source,
            trust_level=trust_level,
            payload_json=json.dumps(payload or {}),
        )
    )


async def resolve_group(db: AsyncSession, group_ref: str) -> TouristGroup:
    ref = group_ref.strip()
    invite = _normalize_invite(ref)
    result = await db.execute(
        select(TouristGroup).where(
            (TouristGroup.group_id == ref) | (TouristGroup.invite_code == invite)
        )
    )
    group = result.scalar_one_or_none()
    if not group:
        raise HTTPException(status_code=404, detail="Group not found")
    return group


async def get_active_member(
    db: AsyncSession,
    group_id: str,
    tourist_id: str,
) -> Optional[TouristGroupMember]:
    result = await db.execute(
        select(TouristGroupMember).where(
            TouristGroupMember.group_id == group_id,
            TouristGroupMember.tourist_id == tourist_id,
            TouristGroupMember.left_at.is_(None),
        )
    )
    return result.scalar_one_or_none()


async def get_active_group_for_tourist(
    db: AsyncSession,
    tourist_id: str,
) -> Optional[TouristGroup]:
    result = await db.execute(
        select(TouristGroup)
        .join(TouristGroupMember, TouristGroupMember.group_id == TouristGroup.group_id)
        .where(
            TouristGroupMember.tourist_id == tourist_id,
            TouristGroupMember.left_at.is_(None),
            TouristGroup.status == ACTIVE,
        )
        .order_by(TouristGroupMember.joined_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


async def create_group(
    db: AsyncSession,
    tourist_id: str,
    name: Optional[str] = None,
    trip_id: Optional[str] = None,
    destination_id: Optional[str] = None,
) -> dict:
    existing = await get_active_group_for_tourist(db, tourist_id)
    if existing:
        raise HTTPException(status_code=409, detail="Tourist already has an active group")

    tourist = await _get_tourist(db, tourist_id)
    now = _now()
    group_id = f"GRP-{random.SystemRandom().randint(10**9, 10**10 - 1)}"
    invite_code = await _generate_invite_code(db)
    group = TouristGroup(
        group_id=group_id,
        name=(name or "Travel Group").strip()[:120] or "Travel Group",
        invite_code=invite_code,
        invite_expires_at=now + datetime.timedelta(hours=INVITE_TTL_HOURS),
        trip_id=trip_id,
        destination_id=destination_id,
        created_by_tourist_id=tourist_id,
        status=ACTIVE,
    )
    db.add(group)
    db.add(
        TouristGroupMember(
            group_id=group_id,
            tourist_id=tourist_id,
            tuid=tourist.tuid,
            display_name=tourist.full_name,
            role="OWNER",
            sharing_status=SHARING,
            last_seen_at=now,
        )
    )
    await db.flush()
    await _log_event(db, group_id, "group_created", tourist_id, payload={"invite_code": invite_code})
    await _log_event(db, group_id, "member_joined", tourist_id, payload={"role": "OWNER"})
    return await get_group_payload(db, group_id, current_tourist_id=tourist_id)


def _record_failed_join(tourist_id: str, invite_code: str) -> None:
    key = f"{tourist_id}:{invite_code}"
    cutoff = time.time() - JOIN_FAILURE_WINDOW_SECONDS
    attempts = [ts for ts in _failed_join_attempts.get(key, []) if ts >= cutoff]
    attempts.append(time.time())
    _failed_join_attempts[key] = attempts


def _assert_join_not_locked(tourist_id: str, invite_code: str) -> None:
    key = f"{tourist_id}:{invite_code}"
    cutoff = time.time() - JOIN_FAILURE_WINDOW_SECONDS
    attempts = [ts for ts in _failed_join_attempts.get(key, []) if ts >= cutoff]
    _failed_join_attempts[key] = attempts
    if len(attempts) >= JOIN_FAILURE_LIMIT:
        raise HTTPException(status_code=429, detail="Too many failed group join attempts. Try again later.")


async def join_group(
    db: AsyncSession,
    invite_code: str,
    tourist_id: str,
) -> dict:
    normalized = _normalize_invite(invite_code)
    _assert_join_not_locked(tourist_id, normalized)
    tourist = await _get_tourist(db, tourist_id)

    result = await db.execute(select(TouristGroup).where(TouristGroup.invite_code == normalized))
    group = result.scalar_one_or_none()
    if not group or group.status != ACTIVE or group.invite_expires_at < _now():
        _record_failed_join(tourist_id, normalized)
        raise HTTPException(status_code=404, detail="Group invite not found or expired")

    existing_active = await get_active_group_for_tourist(db, tourist_id)
    if existing_active and existing_active.group_id != group.group_id:
        raise HTTPException(status_code=409, detail="Tourist already has an active group")

    active_member = await get_active_member(db, group.group_id, tourist_id)
    if active_member:
        return await get_group_payload(db, group.group_id, current_tourist_id=tourist_id)

    active_count = await db.scalar(
        select(func.count())
        .select_from(TouristGroupMember)
        .where(TouristGroupMember.group_id == group.group_id, TouristGroupMember.left_at.is_(None))
    ) or 0
    if active_count >= MAX_GROUP_MEMBERS:
        raise HTTPException(status_code=409, detail=f"Group member limit reached ({MAX_GROUP_MEMBERS})")

    previous = await db.scalar(
        select(TouristGroupMember).where(
            TouristGroupMember.group_id == group.group_id,
            TouristGroupMember.tourist_id == tourist_id,
        )
    )
    now = _now()
    if previous:
        previous.left_at = None
        previous.joined_at = now
        previous.last_seen_at = now
        previous.display_name = tourist.full_name
        previous.tuid = tourist.tuid
        previous.sharing_status = SHARING
    else:
        db.add(
            TouristGroupMember(
                group_id=group.group_id,
                tourist_id=tourist_id,
                tuid=tourist.tuid,
                display_name=tourist.full_name,
                role="MEMBER",
                sharing_status=SHARING,
                last_seen_at=now,
            )
        )
    await db.flush()
    await _log_event(db, group.group_id, "member_joined", tourist_id)
    return await get_group_payload(db, group.group_id, current_tourist_id=tourist_id)


async def set_sharing_status(
    db: AsyncSession,
    group_ref: str,
    tourist_id: str,
    sharing: Optional[bool] = None,
    sharing_status: Optional[str] = None,
) -> dict:
    group = await resolve_group(db, group_ref)
    member = await get_active_member(db, group.group_id, tourist_id)
    if not member:
        raise HTTPException(status_code=403, detail="Tourist is not an active group member")
    next_status = sharing_status or (SHARING if sharing is not False else PAUSED)
    next_status = next_status.strip().upper()
    if next_status not in {SHARING, PAUSED}:
        raise HTTPException(status_code=400, detail="Invalid sharing status")
    if member.sharing_status != next_status:
        member.sharing_status = next_status
        member.last_seen_at = _now()
        await _log_event(
            db,
            group.group_id,
            "sharing_resumed" if next_status == SHARING else "sharing_paused",
            tourist_id,
        )
    return await get_group_payload(db, group.group_id, current_tourist_id=tourist_id)


async def leave_group(db: AsyncSession, group_ref: str, tourist_id: str) -> dict:
    group = await resolve_group(db, group_ref)
    member = await get_active_member(db, group.group_id, tourist_id)
    if not member:
        raise HTTPException(status_code=404, detail="Active group membership not found")
    now = _now()
    member.left_at = now
    member.last_seen_at = now
    member.sharing_status = PAUSED
    snapshot = await db.get(
        TouristGroupLocationSnapshot,
        {"group_id": group.group_id, "tourist_id": tourist_id},
    )
    if snapshot:
        await db.delete(snapshot)
    await _log_event(db, group.group_id, "member_left", tourist_id)

    active_count = await db.scalar(
        select(func.count())
        .select_from(TouristGroupMember)
        .where(TouristGroupMember.group_id == group.group_id, TouristGroupMember.left_at.is_(None))
    ) or 0
    if active_count <= 0:
        group.status = CLOSED
        await _log_event(db, group.group_id, "group_closed", tourist_id)
    return {"status": "left", "group_id": group.group_id}


async def upsert_location_snapshot(
    db: AsyncSession,
    group_ref: str,
    tourist_id: str,
    latitude: float,
    longitude: float,
    accuracy_meters: Optional[float] = None,
    battery_level: Optional[float] = None,
    zone_status: Optional[str] = None,
    client_timestamp: Optional[datetime.datetime] = None,
    source: str = SOURCE_WEBSOCKET,
    trust_level: str = TRUST_CONFIRMED,
) -> dict:
    group = await resolve_group(db, group_ref)
    if group.status != ACTIVE:
        raise HTTPException(status_code=409, detail="Group is not active")
    member = await get_active_member(db, group.group_id, tourist_id)
    if not member:
        raise HTTPException(status_code=403, detail="Tourist is not an active group member")

    now = _now()
    member.last_seen_at = now

    if member.sharing_status != SHARING:
        return {
            "accepted": False,
            "rate_limited": False,
            "reason": "sharing_paused",
            "group": await get_group_payload(db, group.group_id, current_tourist_id=tourist_id),
        }

    snapshot = await db.get(
        TouristGroupLocationSnapshot,
        {"group_id": group.group_id, "tourist_id": tourist_id},
    )
    if snapshot and snapshot.server_updated_at:
        elapsed = (now - snapshot.server_updated_at).total_seconds()
        if elapsed < LOCATION_UPDATE_MIN_SECONDS:
            return {
                "accepted": False,
                "rate_limited": True,
                "reason": "location_update_rate_limited",
                "group": await get_group_payload(db, group.group_id, current_tourist_id=tourist_id),
            }

    if snapshot:
        snapshot.latitude = latitude
        snapshot.longitude = longitude
        snapshot.accuracy_meters = accuracy_meters
        snapshot.battery_level = battery_level
        snapshot.zone_status = (zone_status or "UNKNOWN").upper()
        snapshot.source = source
        snapshot.trust_level = trust_level
        snapshot.client_timestamp = client_timestamp or now
        snapshot.server_updated_at = now
    else:
        db.add(
            TouristGroupLocationSnapshot(
                group_id=group.group_id,
                tourist_id=tourist_id,
                latitude=latitude,
                longitude=longitude,
                accuracy_meters=accuracy_meters,
                battery_level=battery_level,
                zone_status=(zone_status or "UNKNOWN").upper(),
                source=source,
                trust_level=trust_level,
                client_timestamp=client_timestamp or now,
                server_updated_at=now,
            )
        )
    await db.flush()
    return {
        "accepted": True,
        "rate_limited": False,
        "reason": None,
        "group": await get_group_payload(db, group.group_id, current_tourist_id=tourist_id),
    }


async def record_group_event(
    db: AsyncSession,
    group_ref: str,
    tourist_id: Optional[str],
    event_type: str,
    source: str = "server",
    trust_level: str = TRUST_CONFIRMED,
    payload: Optional[dict] = None,
) -> None:
    group = await resolve_group(db, group_ref)
    await _log_event(db, group.group_id, event_type, tourist_id, source, trust_level, payload)


async def assert_group_member(db: AsyncSession, group_ref: str, tourist_id: str) -> TouristGroup:
    group = await resolve_group(db, group_ref)
    member = await get_active_member(db, group.group_id, tourist_id)
    if not member:
        raise HTTPException(status_code=403, detail="Tourist is not an active group member")
    return group


async def get_group_payload(
    db: AsyncSession,
    group_ref: str,
    current_tourist_id: Optional[str] = None,
) -> dict:
    group = await resolve_group(db, group_ref)
    members_result = await db.execute(
        select(TouristGroupMember)
        .where(TouristGroupMember.group_id == group.group_id, TouristGroupMember.left_at.is_(None))
        .order_by(TouristGroupMember.joined_at.asc())
    )
    members = members_result.scalars().all()
    snapshots_result = await db.execute(
        select(TouristGroupLocationSnapshot).where(TouristGroupLocationSnapshot.group_id == group.group_id)
    )
    snapshots = {snapshot.tourist_id: snapshot for snapshot in snapshots_result.scalars().all()}
    serialized_members = [_serialize_member(member, snapshots.get(member.tourist_id)) for member in members]
    return {
        "group_id": group.group_id,
        "room_id": group.invite_code,
        "invite_code": group.invite_code,
        "invite_expires_at": _iso(group.invite_expires_at),
        "name": group.name,
        "trip_id": group.trip_id,
        "destination_id": group.destination_id,
        "created_by_tourist_id": group.created_by_tourist_id,
        "status": group.status,
        "created_at": _iso(group.created_at),
        "updated_at": _iso(group.updated_at),
        "members": serialized_members,
        "current_member": next(
            (member for member in serialized_members if member["tourist_id"] == current_tourist_id),
            None,
        ),
        "limits": {
            "max_members": MAX_GROUP_MEMBERS,
            "stale_signal_seconds": STALE_SIGNAL_SECONDS,
            "location_update_min_seconds": LOCATION_UPDATE_MIN_SECONDS,
        },
    }


def _serialize_member(
    member: TouristGroupMember,
    snapshot: Optional[TouristGroupLocationSnapshot],
) -> dict:
    now = _now()
    timestamp = snapshot.client_timestamp if snapshot else member.last_seen_at
    updated_at = snapshot.server_updated_at if snapshot else member.last_seen_at
    is_stale = True
    if updated_at:
        is_stale = (now - updated_at).total_seconds() > STALE_SIGNAL_SECONDS
    latitude = snapshot.latitude if snapshot else None
    longitude = snapshot.longitude if snapshot else None
    return {
        "tourist_id": member.tourist_id,
        "user_id": member.tourist_id,
        "tuid": member.tuid,
        "display_name": member.display_name,
        "name": member.display_name,
        "role": member.role,
        "sharing_status": member.sharing_status,
        "lat": latitude,
        "lng": longitude,
        "latitude": latitude,
        "longitude": longitude,
        "accuracy_meters": snapshot.accuracy_meters if snapshot else None,
        "battery_level": snapshot.battery_level if snapshot else None,
        "zone_status": snapshot.zone_status if snapshot else None,
        "source": snapshot.source if snapshot else None,
        "trust_level": snapshot.trust_level if snapshot else None,
        "timestamp": timestamp.timestamp() if timestamp else None,
        "client_timestamp": _iso(timestamp),
        "last_seen_at": _iso(member.last_seen_at),
        "server_updated_at": _iso(updated_at),
        "is_stale": is_stale,
    }
