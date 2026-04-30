# backend/routers/trail_graphs.py
# Per-destination trail graph — authority uploads GeoJSON, tourists download for offline nav.

import uuid, json, datetime
from fastapi import APIRouter, HTTPException, Security, UploadFile, File
from backend.database import get_db
from backend.auth import require_authority, require_tourist

router = APIRouter(prefix="/destinations", tags=["Trail Graphs"])


@router.post("/{dest_id}/trail-graph")
async def upload_trail_graph(
    dest_id: str,
    file: UploadFile = File(..., description="GeoJSON or SafeRoute graph JSON"),
    user: dict = Security(require_authority),
):
    """
    Upload or replace the trail graph for a destination.
    Accepts either:
    - SafeRoute format: {"nodes":[...], "edges":[...]}
    - GeoJSON FeatureCollection (nodes as Point features, edges as LineString features)
    """
    _assert_jurisdiction(dest_id, user["sub"])

    raw = await file.read()
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        raise HTTPException(400, "Invalid JSON file")

    graph = _normalise_graph(data, dest_id)

    gid = str(uuid.uuid4())
    now = datetime.datetime.now().isoformat()
    with get_db() as conn:
        existing = conn.execute(
            "SELECT id, version FROM trail_graphs WHERE destination_id=?", (dest_id,)
        ).fetchone()
        new_version = (existing["version"] + 1) if existing else 1
        conn.execute(
            "INSERT OR REPLACE INTO trail_graphs (id,destination_id,version,graph_json,created_at) VALUES (?,?,?,?,?)",
            (gid, dest_id, new_version, json.dumps(graph), now)
        )
        conn.commit()
    return {
        "id": gid,
        "destination_id": dest_id,
        "version": new_version,
        "node_count": len(graph["nodes"]),
        "edge_count": len(graph["edges"]),
    }


@router.get("/{dest_id}/trail-graph")
async def get_trail_graph(dest_id: str, _tid: str = Security(require_tourist)):
    """Download the trail graph for offline pathfinding."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM trail_graphs WHERE destination_id=?", (dest_id,)
        ).fetchone()
    if not row:
        raise HTTPException(404, f"No trail graph for destination {dest_id}")
    graph = json.loads(row["graph_json"])
    return {
        "id":             row["id"],
        "destination_id": dest_id,
        "version":        row["version"],
        "created_at":     row["created_at"],
        **graph,
    }


# ── Helpers ───────────────────────────────────────────────────────────────────

def _assert_jurisdiction(dest_id: str, authority_id: str):
    with get_db() as conn:
        row = conn.execute(
            "SELECT authority_id FROM destinations WHERE id=?", (dest_id,)
        ).fetchone()
    if not row:
        raise HTTPException(404, "Destination not found")
    if row["authority_id"] != authority_id:
        raise HTTPException(403, "You do not have jurisdiction over this destination")


def _normalise_graph(data: dict, dest_id: str) -> dict:
    """Accept both SafeRoute native format and GeoJSON FeatureCollection."""
    if "nodes" in data and "edges" in data:
        # Already SafeRoute format — validate and return
        for n in data["nodes"]:
            if not all(k in n for k in ("id", "lat", "lng")):
                raise HTTPException(400, "Each node must have id, lat, lng")
            n.setdefault("zone_type", "SAFE")
            n.setdefault("name", n["id"])
        for e in data["edges"]:
            if not all(k in e for k in ("from_node_id", "to_node_id", "weight_meters")):
                # also accept legacy keys
                if "from" in e and "to" in e and "weight" in e:
                    e["from_node_id"] = e.pop("from")
                    e["to_node_id"]   = e.pop("to")
                    e["weight_meters"] = e.pop("weight")
                else:
                    raise HTTPException(400, "Each edge must have from_node_id, to_node_id, weight_meters")
            e.setdefault("offline_path", [])
        return {"nodes": data["nodes"], "edges": data["edges"]}

    if data.get("type") == "FeatureCollection":
        return _from_geojson(data, dest_id)

    raise HTTPException(400, "Unrecognised format. Use SafeRoute graph JSON or GeoJSON FeatureCollection.")


def _from_geojson(fc: dict, dest_id: str) -> dict:
    """
    GeoJSON convention:
    - Point features → nodes (properties: id, name, zone_type)
    - LineString features → edges (properties: from_node_id, to_node_id, weight_meters)
    """
    import math

    def _haversine(c1, c2):
        R = 6371000
        lat1, lng1 = math.radians(c1[1]), math.radians(c1[0])
        lat2, lng2 = math.radians(c2[1]), math.radians(c2[0])
        dlat, dlng = lat2 - lat1, lng2 - lng1
        a = math.sin(dlat/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin(dlng/2)**2
        return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

    nodes, edges = [], []
    for feat in fc.get("features", []):
        geom = feat.get("geometry", {})
        props = feat.get("properties", {})
        if geom["type"] == "Point":
            lng, lat = geom["coordinates"]
            nodes.append({
                "id":        props.get("id", str(uuid.uuid4())[:8]),
                "lat":       lat,
                "lng":       lng,
                "zone_type": props.get("zone_type", "SAFE"),
                "name":      props.get("name", ""),
            })
        elif geom["type"] == "LineString":
            coords = geom["coordinates"]
            weight = props.get("weight_meters") or _haversine(coords[0], coords[-1])
            edges.append({
                "from_node_id":  props.get("from_node_id", ""),
                "to_node_id":    props.get("to_node_id", ""),
                "weight_meters": weight,
                "offline_path":  [{"lat": c[1], "lng": c[0]} for c in coords],
            })
    return {"nodes": nodes, "edges": edges}
