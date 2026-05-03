# backend/routers/location.py

import datetime
from fastapi import APIRouter, HTTPException, Security
from pydantic import BaseModel
from backend.database import get_db
from backend.auth import require_tourist

router = APIRouter(prefix="/location", tags=["Location"])


class LocationPing(BaseModel):
    tourist_id:      str
    latitude:        float
    longitude:       float
    speed_kmh:       float = 0
    accuracy_meters: float = 0
    timestamp:       str
    zone_status:     str = "UNKNOWN"
    destination_id:  str = ""


@router.post("/ping")
async def receive_ping(
    ping: LocationPing,
    tourist_id: str = Security(require_tourist),
):
    if ping.tourist_id != tourist_id:
        raise HTTPException(403, "Tourist ID mismatch")

    with get_db() as conn:
        conn.execute(
            """INSERT INTO location_logs
               (tourist_id,latitude,longitude,speed_kmh,zone_status,timestamp)
               VALUES (?,?,?,?,?,?)""",
            (tourist_id, ping.latitude, ping.longitude,
             ping.speed_kmh, ping.zone_status, ping.timestamp)
        )
        conn.commit()
    return {"status": "received"}
