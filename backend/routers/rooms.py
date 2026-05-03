# backend/routers/rooms.py
# Group tour WebSocket rooms — unchanged in logic, cleaned up.

import uuid, json, time
from fastapi import APIRouter, WebSocket, WebSocketDisconnect, HTTPException, Security
from typing import Dict, List, Optional
from backend.auth import require_tourist, decode_token

router = APIRouter(tags=["Group Rooms"])

rooms:       Dict[str, Dict[str, dict]] = {}
connections: Dict[str, List[WebSocket]] = {}


@router.post("/rooms/create")
async def create_room(tourist_id: str = Security(require_tourist)):
    room_id = uuid.uuid4().hex[:6].upper()
    rooms[room_id]       = {}
    connections[room_id] = []
    return {"room_id": room_id}


@router.post("/rooms/{room_id}/join")
async def join_room(room_id: str, tourist_id: str = Security(require_tourist)):
    if room_id not in rooms:
        raise HTTPException(404, "Room not found")
    return {"status": "ok", "room_id": room_id, "user_id": tourist_id}


@router.websocket("/ws/{room_id}/{user_id}")
async def room_websocket(
    websocket: WebSocket,
    room_id: str,
    user_id: str,
    token: Optional[str] = None,
):
    # Validate JWT from query param (WebSocket limitation)
    payload = decode_token(token or "")
    if not payload or payload["sub"] != user_id:
        await websocket.close(code=4003)
        return

    await websocket.accept()

    if room_id not in rooms:
        await websocket.close(code=4004)
        return

    connections.setdefault(room_id, []).append(websocket)

    try:
        while True:
            data = await websocket.receive_text()
            msg  = json.loads(data)
            rooms[room_id][user_id] = {
                "user_id":   user_id,
                "name":      msg.get("name", "Unknown"),
                "lat":       float(msg["lat"]),
                "lng":       float(msg["lng"]),
                "timestamp": time.time(),
            }
            broadcast = json.dumps({"type": "location_update", "members": list(rooms[room_id].values())})
            dead: List[WebSocket] = []
            for conn in connections[room_id]:
                try:
                    await conn.send_text(broadcast)
                except Exception:
                    dead.append(conn)
            for d in dead:
                connections[room_id].remove(d)

    except WebSocketDisconnect:
        connections.get(room_id, []).remove(websocket) if websocket in connections.get(room_id, []) else None
        rooms[room_id].pop(user_id, None)
        broadcast = json.dumps({"type": "member_left", "user_id": user_id, "members": list(rooms[room_id].values())})
        for conn in connections.get(room_id, []):
            try:
                await conn.send_text(broadcast)
            except Exception:
                pass
