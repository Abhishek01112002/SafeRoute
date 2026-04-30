# backend/routers/zones.py
# Zone CRUD — authority-managed, jurisdiction-enforced.
# Tourists call GET /zones/lookup?lat=&lng= for point-in-zone queries.

import uuid, json, datetime, math
from fastapi import APIRouter, HTTPException, Security, Query
from pydantic import BaseModel
from typing import Optional, List
from backend.database import get_db
from backend.auth import require_authority, require_tourist

router = APIRouter(prefix="/zones", tags=["Zones"])


class ZonePoint(BaseModel):
    lat: float
    lng: float


class ZoneCreate(BaseModel):
    destination_id: str
    name:           str
    type:           str   # SAFE | CAUTION | RESTRICTED
    shape:          str = "CIRCLE"
    center_lat:     Optional[float] = None
    center_lng:     Optional[float] = None
    radius_m:       Optional[float] = None
    polygon_points: List[ZonePoint] = []


# ── Authority endpoints ───────────────────────────────────────────────────────

@router.post("")
async def create_zone(body: ZoneCreate, user: dict = Security(require_authority)):
    _assert_jurisdiction(body.destination_id, user["sub"])
    _validate_shape(body)
    zone_id = str(uuid.uuid4())
    now = datetime.datetime.now().isoformat()
    with get_db() as conn:
        conn.execute(
            """INSERT INTO zones
               (id,destination_id,authority_id,name,type,shape,
                center_lat,center_lng,radius_m,polygon_json,is_active,created_at,updated_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,1,?,?)""",
            (zone_id, body.destination_id, user["sub"], body.name, body.type.upper(),
             body.shape.upper(), body.center_lat, body.center_lng, body.radius_m,
             json.dumps([p.dict() for p in body.polygon_points]), now, now)
        )
        conn.commit()
    return {"id": zone_id, "message": "Zone created"}


@router.get("")
async def list_zones(destination_id: str = Query(...)):
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM zones WHERE destination_id=? AND is_active=1", (destination_id,)
        ).fetchall()
    return [_parse_zone(dict(r)) for r in rows]


@router.put("/{zone_id}")
async def update_zone(zone_id: str, body: dict, user: dict = Security(require_authority)):
    with get_db() as conn:
        row = conn.execute("SELECT * FROM zones WHERE id=?", (zone_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Zone not found")
        if row["authority_id"] != user["sub"]:
            raise HTTPException(403, "Jurisdiction mismatch")
        allowed = {"name", "type", "shape", "center_lat", "center_lng", "radius_m", "polygon_points"}
        updates = {k: v for k, v in body.items() if k in allowed}
        if "polygon_points" in updates:
            updates["polygon_json"] = json.dumps(updates.pop("polygon_points"))
        if "type" in updates:
            updates["type"] = updates["type"].upper()
        updates["updated_at"] = datetime.datetime.now().isoformat()
        sets = ", ".join(f"{k}=?" for k in updates)
        conn.execute(f"UPDATE zones SET {sets} WHERE id=?", [*updates.values(), zone_id])
        conn.commit()
    return {"message": "Zone updated"}


@router.delete("/{zone_id}")
async def delete_zone(zone_id: str, user: dict = Security(require_authority)):
    with get_db() as conn:
        row = conn.execute("SELECT authority_id FROM zones WHERE id=?", (zone_id,)).fetchone()
        if not row:
            raise HTTPException(404, "Zone not found")
        if row["authority_id"] != user["sub"]:
            raise HTTPException(403, "Jurisdiction mismatch")
        conn.execute("UPDATE zones SET is_active=0 WHERE id=?", (zone_id,))
        conn.commit()
    return {"message": "Zone deactivated"}


# ── Tourist endpoint ──────────────────────────────────────────────────────────

@router.get("/lookup")
async def lookup_zone(
    lat: float = Query(...),
    lng: float = Query(...),
    destination_id: str = Query(...),
    _tid: str = Security(require_tourist),
):
    """Return zone type for a GPS point within a destination."""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM zones WHERE destination_id=? AND is_active=1 ORDER BY type",
            (destination_id,)
        ).fetchall()

    # Priority: RESTRICTED > CAUTION > SAFE
    priority = {"RESTRICTED": 3, "CAUTION": 2, "SAFE": 1}
    matched = []
    for r in rows:
        z = _parse_zone(dict(r))
        if _point_in_zone(lat, lng, z):
            matched.append(z)

    if not matched:
        return {"zone_type": "UNKNOWN", "zone_name": None}

    best = max(matched, key=lambda z: priority.get(z["type"], 0))
    return {"zone_type": best["type"], "zone_name": best["name"], "zone_id": best["id"]}


# ── Helpers ───────────────────────────────────────────────────────────────────

def _assert_jurisdiction(destination_id: str, authority_id: str):
    with get_db() as conn:
        row = conn.execute(
            "SELECT authority_id FROM destinations WHERE id=?", (destination_id,)
        ).fetchone()
    if not row:
        raise HTTPException(404, "Destination not found")
    if row["authority_id"] != authority_id:
        raise HTTPException(403, "You do not have jurisdiction over this destination")


def _validate_shape(body: ZoneCreate):
    if body.shape.upper() == "CIRCLE":
        if body.center_lat is None or body.center_lng is None or body.radius_m is None:
            raise HTTPException(400, "Circle zones require center_lat, center_lng, radius_m")
    elif body.shape.upper() == "POLYGON":
        if len(body.polygon_points) < 3:
            raise HTTPException(400, "Polygon zones require at least 3 points")
    else:
        raise HTTPException(400, "shape must be CIRCLE or POLYGON")


def _parse_zone(r: dict) -> dict:
    try:
        r["polygon_points"] = json.loads(r.pop("polygon_json", "[]"))
    except Exception:
        r["polygon_points"] = []
    return r


def _haversine_m(lat1, lng1, lat2, lng2) -> float:
    R = 6371000
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp/2)**2 + math.cos(p1)*math.cos(p2)*math.sin(dl/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _point_in_zone(lat: float, lng: float, zone: dict) -> bool:
    if zone["shape"] == "CIRCLE":
        clat, clng, r = zone.get("center_lat"), zone.get("center_lng"), zone.get("radius_m")
        if None in (clat, clng, r):
            return False
        return _haversine_m(lat, lng, clat, clng) <= r
    # POLYGON — ray-casting
    points = zone.get("polygon_points", [])
    if len(points) < 3:
        return False
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]["lng"], points[i]["lat"]
        xj, yj = points[j]["lng"], points[j]["lat"]
        if ((yi > lat) != (yj > lat)) and (lng < (xj - xi) * (lat - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside
