# backend/routers/sos.py
# SOS trigger (tourist) + event management (authority only).

import datetime
from fastapi import APIRouter, HTTPException, Body, Security
from typing import Optional
from backend.database import get_db
from backend.auth import require_tourist, require_authority
from backend.notifications import dispatch_sos

router = APIRouter(prefix="/sos", tags=["SOS"])


@router.post("/trigger")
async def trigger_sos(
    payload: dict = Body(...),
    tourist_id: str = Security(require_tourist),
):
    lat          = payload.get("latitude")
    lng          = payload.get("longitude")
    trigger_type = payload.get("trigger_type", "MANUAL")
    dest_id      = payload.get("destination_id")

    if lat is None or lng is None:
        raise HTTPException(400, "latitude and longitude are required")

    now = datetime.datetime.now().isoformat()

    with get_db() as conn:
        # Persist SOS event
        cursor = conn.execute(
            """INSERT INTO sos_events
               (tourist_id,latitude,longitude,trigger_type,timestamp,status,destination_id)
               VALUES (?,?,?,?,?,'ACTIVE',?)""",
            (tourist_id, float(lat), float(lng), trigger_type, now, dest_id)
        )
        sos_id = cursor.lastrowid

        # Get tourist name
        t_row = conn.execute("SELECT data FROM tourists WHERE tourist_id=?", (tourist_id,)).fetchone()
        tourist_name = "Unknown Tourist"
        if t_row:
            import json
            tourist_name = json.loads(t_row["data"]).get("full_name", tourist_name)

        # Get authorities for this destination (district-level jurisdiction)
        authorities = []
        if dest_id:
            authorities = conn.execute("""
                SELECT a.fcm_token, a.phone
                FROM authorities a
                JOIN destinations d ON d.authority_id = a.authority_id
                WHERE d.id = ? AND a.status = 'active'
            """, (dest_id,)).fetchall()

        conn.commit()

    # Dispatch notifications async-style (non-blocking in production use BackgroundTasks)
    fcm_tokens = [a["fcm_token"] for a in authorities if a["fcm_token"]]
    phones     = [a["phone"]     for a in authorities if a["phone"]]
    dispatch_sos(tourist_id, tourist_name, float(lat), float(lng), trigger_type, fcm_tokens, phones)

    print(f"[!!! SOS !!!] id={sos_id} tourist={tourist_id} @ ({lat},{lng}) type={trigger_type}")
    return {
        "sos_id":    sos_id,
        "status":    "ACTIVE",
        "tourist_id": tourist_id,
        "timestamp": now,
    }


@router.get("/events")
async def list_sos_events(
    user: dict = Security(require_authority),
):
    """List SOS events within the authority's jurisdiction."""
    with get_db() as conn:
        # Only show events from destinations under this authority's jurisdiction
        rows = conn.execute("""
            SELECT s.* FROM sos_events s
            LEFT JOIN destinations d ON d.id = s.destination_id
            WHERE d.authority_id = ? OR s.destination_id IS NULL
            ORDER BY s.id DESC LIMIT 200
        """, (user["sub"],)).fetchall()
    return [dict(r) for r in rows]


@router.post("/events/{sos_id}/respond")
async def respond_to_sos(
    sos_id: int,
    user: dict = Security(require_authority),
):
    """Authority acknowledges and closes an SOS event."""
    with get_db() as conn:
        row = conn.execute("SELECT * FROM sos_events WHERE id=?", (sos_id,)).fetchone()
        if not row:
            raise HTTPException(404, "SOS event not found")
        if row["status"] == "RESOLVED":
            return {"message": "Already resolved"}
        conn.execute(
            "UPDATE sos_events SET status='RESOLVED', responded_by=?, responded_at=? WHERE id=?",
            (user["sub"], datetime.datetime.now().isoformat(), sos_id)
        )
        conn.commit()
    return {"sos_id": sos_id, "status": "RESOLVED"}
