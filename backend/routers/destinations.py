# backend/routers/destinations.py

import uuid, json, datetime
from fastapi import APIRouter, HTTPException, Security
from pydantic import BaseModel
from typing import Optional, List
from backend.database import get_db
from backend.auth import require_authority

router = APIRouter(prefix="/destinations", tags=["Destinations"])


class DestinationCreate(BaseModel):
    id:           Optional[str] = None   # auto-generated if omitted
    state:        str
    name:         str
    district:     str
    altitude_m:   int = 0
    center_lat:   float
    center_lng:   float
    category:     str = ""
    difficulty:   str = "LOW"
    connectivity: str = "MODERATE"
    best_season:  str = ""
    warnings:     List[str] = []


@router.get("/states")
async def get_states():
    with get_db() as conn:
        rows = conn.execute(
            "SELECT DISTINCT state FROM destinations WHERE is_active=1 ORDER BY state"
        ).fetchall()
    return [r["state"] for r in rows]


@router.get("/{state}")
async def get_destinations_by_state(state: str):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM destinations WHERE state=? AND is_active=1", (state,)
        ).fetchall()
    if not rows:
        raise HTTPException(404, f"No destinations found for state: {state}")
    return [_enrich(dict(r)) for r in rows]


@router.get("/{dest_id}/detail")
async def get_destination_detail(dest_id: str):
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM destinations WHERE id=? AND is_active=1", (dest_id,)
        ).fetchone()
    if not row:
        raise HTTPException(404, "Destination not found")
    d = _enrich(dict(row))
    with get_db() as conn:
        contacts = conn.execute(
            "SELECT * FROM emergency_contacts WHERE destination_id=?", (dest_id,)
        ).fetchall()
    d["emergency_contacts"] = [dict(c) for c in contacts]
    return d


@router.post("")
async def create_destination(
    body: DestinationCreate,
    user: dict = Security(require_authority),
):
    dest_id = body.id or f"{body.state[:2].upper()}_{uuid.uuid4().hex[:6].upper()}"
    with get_db() as conn:
        existing = conn.execute("SELECT id FROM destinations WHERE id=?", (dest_id,)).fetchone()
        if existing:
            raise HTTPException(400, f"Destination ID '{dest_id}' already exists")
        conn.execute(
            """INSERT INTO destinations
               (id,state,name,district,altitude_m,center_lat,center_lng,
                category,difficulty,connectivity,best_season,warnings_json,authority_id,is_active)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,1)""",
            (dest_id, body.state, body.name, body.district, body.altitude_m,
             body.center_lat, body.center_lng, body.category, body.difficulty,
             body.connectivity, body.best_season, json.dumps(body.warnings), user["sub"])
        )
        conn.commit()
    return {"id": dest_id, "message": "Destination created"}


@router.put("/{dest_id}")
async def update_destination(
    dest_id: str,
    body: dict,
    user: dict = Security(require_authority),
):
    with get_db() as conn:
        row = conn.execute("SELECT authority_id FROM destinations WHERE id=?", (dest_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Destination not found")
        if row["authority_id"] != user["sub"]:
            raise HTTPException(403, "You do not have jurisdiction over this destination")
        allowed = {"name","district","altitude_m","category","difficulty","connectivity","best_season","warnings"}
        sets = ", ".join(f"{k}=?" for k in body if k in allowed)
        vals = [body[k] for k in body if k in allowed]
        if sets:
            if "warnings" in body:
                idx = list(body.keys()).index("warnings")
                vals[idx] = json.dumps(body["warnings"])
            conn.execute(f"UPDATE destinations SET {sets} WHERE id=?", [*vals, dest_id])
            conn.commit()
    return {"message": "Updated"}


@router.delete("/{dest_id}")
async def deactivate_destination(
    dest_id: str,
    user: dict = Security(require_authority),
):
    with get_db() as conn:
        row = conn.execute("SELECT authority_id FROM destinations WHERE id=?", (dest_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Destination not found")
        if row["authority_id"] != user["sub"]:
            raise HTTPException(403, "Jurisdiction mismatch")
        conn.execute("UPDATE destinations SET is_active=0 WHERE id=?", (dest_id,))
        conn.commit()
    return {"message": "Destination deactivated"}


def _enrich(d: dict) -> dict:
    try:
        d["warnings"] = json.loads(d.pop("warnings_json", "[]"))
    except Exception:
        d["warnings"] = []
    return d
