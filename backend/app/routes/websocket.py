# app/routes/rooms.py
import uuid
import json
import time
from typing import List, Optional
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, HTTPException
from app.dependencies import get_current_tourist
from app.services.jwt_service import verify_jwt_payload
from app.db.sqlite_legacy import rooms, connections

router = APIRouter()

@router.post("/create")
async def create_room(tourist_id: str = Depends(get_current_tourist)):
    room_id = uuid.uuid4().hex[:6].upper()
    rooms[room_id] = {}
    connections[room_id] = []
    return {"room_id": room_id}

@router.post("/{room_id}/join")
async def join_room(room_id: str, tourist_id: str = Depends(get_current_tourist)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    return {"status": "ok", "room_id": room_id, "user_id": tourist_id}

@router.websocket("/ws/{room_id}/{user_id}")
async def room_websocket(websocket: WebSocket, room_id: str, user_id: str, token: Optional[str] = None):
    # Validate token from query param
    payload = verify_jwt_payload(token) if token else None
    subject_id = payload.get("sub") if payload else None
    if not payload or payload.get("type") != "access" or subject_id != user_id:
        await websocket.close(code=4003) # Forbidden
        return

    await websocket.accept()

    if room_id not in rooms:
        await websocket.close(code=4004)
        return

    if room_id not in connections:
        connections[room_id] = []
    connections[room_id].append(websocket)

    try:
        while True:
            data = await websocket.receive_text()
            payload = json.loads(data)

            lat = payload.get("lat")
            lng = payload.get("lng")
            name = payload.get("name", "Unknown")

            if lat is None or lng is None:
                raise HTTPException(status_code=400, detail="lat and lng are required")
            if not isinstance(lat, (int, float)) or not isinstance(lng, (int, float)):
                raise HTTPException(status_code=400, detail="lat and lng must be numbers")
            if not (-90 <= float(lat) <= 90):
                raise HTTPException(status_code=400, detail=f"Invalid latitude: {lat}. Must be between -90 and +90")
            if not (-180 <= float(lng) <= 180):
                raise HTTPException(status_code=400, detail=f"Invalid longitude: {lng}. Must be between -180 and +180")

            if not isinstance(name, str):
                raise HTTPException(status_code=400, detail="name must be a string")
            name = name.strip()
            if not name:
                name = "Unknown"
            if len(name) > 60:
                raise HTTPException(status_code=400, detail="name too long (max 60 characters)")

            # Optional timestamp freshness validation (5-minute skew window)
            client_ts = payload.get("timestamp")
            if client_ts is not None:
                if not isinstance(client_ts, (int, float)):
                    raise HTTPException(status_code=400, detail="timestamp must be unix seconds")
                if abs(time.time() - float(client_ts)) > 300:
                    raise HTTPException(status_code=400, detail="timestamp is too old or too far in the future")

            rooms[room_id][user_id] = {
                "user_id": user_id,
                "tuid": payload.get("tuid"),
                "name": name,
                "lat": float(lat),
                "lng": float(lng),
                "timestamp": float(client_ts) if client_ts is not None else time.time(),
            }

            snapshot = list(rooms[room_id].values())
            broadcast = json.dumps({"type": "location_update", "members": snapshot})

            dead: List[WebSocket] = []
            for conn in connections[room_id]:
                try:
                    await conn.send_text(broadcast)
                except Exception:
                    dead.append(conn)

            for d in dead:
                connections[room_id].remove(d)

    except WebSocketDisconnect:
        if websocket in connections.get(room_id, []):
            connections[room_id].remove(websocket)
        rooms[room_id].pop(user_id, None)

        snapshot = list(rooms[room_id].values())
        broadcast = json.dumps({"type": "member_left", "user_id": user_id, "members": snapshot})
        for conn in connections.get(room_id, []):
            try:
                await conn.send_text(broadcast)
            except Exception:
                pass
