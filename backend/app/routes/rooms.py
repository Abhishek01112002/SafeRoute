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

            rooms[room_id][user_id] = {
                "user_id": user_id,
                "name": payload.get("name", "Unknown"),
                "lat": float(payload["lat"]),
                "lng": float(payload["lng"]),
                "timestamp": time.time(),
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
