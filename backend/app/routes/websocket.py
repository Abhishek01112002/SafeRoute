# app/routes/rooms.py
import datetime
import json
import time
from typing import List, Optional

from fastapi import APIRouter, Body, Depends, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import AsyncSessionLocal, get_db
from app.dependencies import get_current_tourist
from app.services import group_safety
from app.services.jwt_service import verify_jwt_payload


router = APIRouter()

# Live socket registry only. Canonical group state lives in PostgreSQL tables.
connections: dict[str, List[WebSocket]] = {}


@router.post("/create")
async def create_room(
    payload: dict = Body(default_factory=dict),
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    group = await group_safety.create_group(
        db,
        tourist_id=tourist_id,
        name=payload.get("name") or payload.get("room_name"),
        trip_id=payload.get("trip_id"),
        destination_id=payload.get("destination_id"),
    )
    return {
        "room_id": group["invite_code"],
        "group_id": group["group_id"],
        "invite_code": group["invite_code"],
        "members": group["members"],
    }


@router.post("/{room_id}/join")
async def join_room(
    room_id: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    group = await group_safety.join_group(db, invite_code=room_id, tourist_id=tourist_id)
    return {
        "status": "ok",
        "room_id": group["invite_code"],
        "group_id": group["group_id"],
        "user_id": tourist_id,
        "members": group["members"],
    }


@router.websocket("/ws/{room_id}/{user_id}")
async def room_websocket(
    websocket: WebSocket,
    room_id: str,
    user_id: str,
    token: Optional[str] = None,
):
    payload = verify_jwt_payload(token) if token else None
    subject_id = payload.get("sub") if payload else None
    if not payload or payload.get("type") != "access" or subject_id != user_id:
        await websocket.close(code=4003)
        return

    try:
        async with AsyncSessionLocal() as db:
            async with db.begin():
                group = await group_safety.assert_group_member(db, room_id, user_id)
                group_payload = await group_safety.get_group_payload(
                    db,
                    group.group_id,
                    current_tourist_id=user_id,
                )
    except Exception:
        await websocket.close(code=4004)
        return

    await websocket.accept()
    group_id = group_payload["group_id"]
    connections.setdefault(group_id, []).append(websocket)

    await websocket.send_text(_room_message("location_update", group_payload))

    try:
        while True:
            raw = await websocket.receive_text()
            data = json.loads(raw)
            location = _parse_location_payload(data)
            source = str(data.get("source") or group_safety.SOURCE_WEBSOCKET).lower()
            trust_level = group_safety.TRUST_CONFIRMED
            if source == group_safety.SOURCE_MESH:
                trust_level = group_safety.TRUST_MESH if data.get("trusted") is True else group_safety.TRUST_ADVISORY

            async with AsyncSessionLocal() as db:
                async with db.begin():
                    result = await group_safety.upsert_location_snapshot(
                        db,
                        group_ref=group_id,
                        tourist_id=user_id,
                        latitude=location["lat"],
                        longitude=location["lng"],
                        accuracy_meters=location.get("accuracy_meters"),
                        battery_level=location.get("battery_level"),
                        zone_status=location.get("zone_status"),
                        client_timestamp=location.get("timestamp"),
                        source=source,
                        trust_level=trust_level,
                    )
                    group_payload = result["group"]

            if result["accepted"]:
                await _broadcast(group_id, _room_message("location_update", group_payload))
            elif result["rate_limited"]:
                await websocket.send_text(
                    json.dumps(
                        {
                            "type": "rate_limited",
                            "reason": result["reason"],
                            "min_interval_seconds": group_safety.LOCATION_UPDATE_MIN_SECONDS,
                        }
                    )
                )
            else:
                await websocket.send_text(
                    json.dumps({"type": "sharing_paused", "reason": result["reason"], "members": group_payload["members"]})
                )
    except WebSocketDisconnect:
        pass
    except Exception as exc:
        try:
            await websocket.send_text(json.dumps({"type": "error", "detail": str(exc)}))
        except Exception:
            pass
    finally:
        if websocket in connections.get(group_id, []):
            connections[group_id].remove(websocket)


def _parse_location_payload(data: dict) -> dict:
    lat = data.get("lat", data.get("latitude"))
    lng = data.get("lng", data.get("longitude"))
    if lat is None or lng is None:
        raise ValueError("lat and lng are required")
    if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
        raise ValueError("lat and lng must be numbers")
    if not (-90 <= float(lat) <= 90):
        raise ValueError("latitude must be between -90 and +90")
    if not (-180 <= float(lng) <= 180):
        raise ValueError("longitude must be between -180 and +180")

    client_ts = data.get("timestamp")
    timestamp = None
    if client_ts is not None:
        if not isinstance(client_ts, (int, float)):
            raise ValueError("timestamp must be unix seconds")
        if abs(time.time() - float(client_ts)) > 300:
            raise ValueError("timestamp is too old or too far in the future")
        timestamp = datetime.datetime.fromtimestamp(float(client_ts), datetime.timezone.utc).replace(tzinfo=None)

    battery = data.get("battery_level")
    if battery is not None:
        battery = float(battery)
        if battery > 1:
            battery = battery / 100
        battery = max(0.0, min(1.0, battery))

    accuracy = data.get("accuracy_meters")
    if accuracy is not None:
        accuracy = max(0.0, float(accuracy))

    zone_status = data.get("zone_status")
    if isinstance(zone_status, str):
        zone_status = zone_status.strip().upper()

    return {
        "lat": float(lat),
        "lng": float(lng),
        "timestamp": timestamp,
        "accuracy_meters": accuracy,
        "battery_level": battery,
        "zone_status": zone_status,
    }


def _room_message(event_type: str, group_payload: dict) -> str:
    return json.dumps(
        {
            "type": event_type,
            "room_id": group_payload["room_id"],
            "group_id": group_payload["group_id"],
            "invite_code": group_payload["invite_code"],
            "members": group_payload["members"],
        }
    )


async def _broadcast(group_id: str, message: str) -> None:
    dead: List[WebSocket] = []
    for conn in connections.get(group_id, []):
        try:
            await conn.send_text(message)
        except Exception:
            dead.append(conn)
    for conn in dead:
        if conn in connections.get(group_id, []):
            connections[group_id].remove(conn)
