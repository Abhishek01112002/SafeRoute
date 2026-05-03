# app/routes/onboard.py
"""
QR Code Zone Download (Onboarding) Endpoint
============================================
Flow:
  1. Admin generates a QR code for a destination from the dashboard.
     QR encodes:  SAFEROUTE-{destination_id}-{hmac}
     where hmac = HMAC-SHA256(destination_id, JWT_SECRET).

  2. Tourist scans QR → Flutter app sends the full token string to:
     GET /onboard/{token}

  3. Server validates the HMAC, fetches all active zones for the destination,
     and returns a self-contained "zone bundle" the app stores offline.

  4. The bundle includes:
     - Full destination metadata (name, district, altitude, warnings, etc.)
     - All active sub-zones (SAFE / CAUTION / RESTRICTED) with polygon/circle data
     - A bounding box the app can use to pre-cache map tiles
     - A signed expiry timestamp (7 days)
"""

import hmac
import hashlib
import datetime
from fastapi import APIRouter, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud
from app.config import settings

router = APIRouter()


# ---------------------------------------------------------------------------
# Token Helpers
# ---------------------------------------------------------------------------

def _compute_hmac(destination_id: str) -> str:
    """Deterministic HMAC-SHA256 over destination_id using JWT_SECRET."""
    return hmac.new(
        settings.JWT_SECRET.encode(),
        destination_id.encode(),
        hashlib.sha256
    ).hexdigest()


def generate_destination_token(destination_id: str) -> str:
    """
    Produces the QR string that encodes into the QR image:
      SAFEROUTE-{destination_id}-{hmac}
    """
    sig = _compute_hmac(destination_id)
    return f"SAFEROUTE-{destination_id}-{sig}"


def validate_destination_token(token: str) -> str:
    """
    Validates a token and returns the destination_id if valid.
    Raises HTTPException 401 if tampered.

    Expected format: SAFEROUTE-{destination_id}-{hmac}
    Note: destination_id may contain hyphens (e.g. UK-KED-001),
    so we split on the last hyphen-delimited 64-char hex segment.
    """
    prefix = "SAFEROUTE-"
    if not token.startswith(prefix):
        raise HTTPException(status_code=401, detail="Invalid token format")

    rest = token[len(prefix):]  # "{destination_id}-{hmac}"

    # HMAC is always 64 hex chars; split from the right
    if len(rest) < 65 or rest[-65] != "-":
        raise HTTPException(status_code=401, detail="Malformed token")

    destination_id = rest[:-65]
    provided_hmac  = rest[-64:]
    expected_hmac  = _compute_hmac(destination_id)

    if not hmac.compare_digest(provided_hmac, expected_hmac):
        raise HTTPException(status_code=401, detail="Token signature invalid")

    return destination_id


# ---------------------------------------------------------------------------
# Bundle Builder
# ---------------------------------------------------------------------------

def _compute_bbox(destination: dict, zones: list) -> dict:
    """
    Compute a bounding box that encloses the destination center and all zone
    geometries. The app uses this to pre-fetch offline map tiles.
    """
    lats = [destination["center_lat"]]
    lngs = [destination["center_lng"]]

    for z in zones:
        if z["shape"] == "CIRCLE" and z.get("center_lat"):
            # Approximate circle extents in degrees (~111km per degree)
            pad = (z.get("radius_m") or 500) / 111_000
            lats += [z["center_lat"] - pad, z["center_lat"] + pad]
            lngs += [z["center_lng"] - pad, z["center_lng"] + pad]
        else:
            for pt in z.get("polygon_points", []):
                lats.append(pt["lat"])
                lngs.append(pt["lng"])

    margin = 0.005  # ~500m buffer
    return {
        "north": max(lats) + margin,
        "south": min(lats) - margin,
        "east":  max(lngs) + margin,
        "west":  min(lngs) - margin,
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("/{token}")
async def get_zone_bundle(token: str, db: AsyncSession = Depends(get_db)):
    """
    Public endpoint — no auth header required (token IS the auth).
    Called by the Flutter app immediately after QR scan.

    Returns a full offline zone bundle for the destination.
    """
    destination_id = validate_destination_token(token)

    # Fetch destination metadata
    destinations = await crud.get_destinations(db, state=None)
    destination = next((d for d in destinations if d["id"] == destination_id), None)
    if not destination:
        raise HTTPException(status_code=404, detail="Destination not found")

    # Fetch all active zones for this destination
    zones = await crud.get_zones(db, destination_id)

    # Compute spatial bounding box for tile pre-caching
    bbox = _compute_bbox(destination, zones)

    expires_at = (
        datetime.datetime.utcnow() + datetime.timedelta(days=7)
    ).isoformat() + "Z"

    return {
        "token_valid": True,
        "destination": destination,
        "zones": zones,
        "zone_count": len(zones),
        "tile_bbox": bbox,
        "tile_zoom_range": [10, 16],   # Zoom levels for offline tile cache
        "tile_cache_url": None,         # Optional: CDN URL for pre-packed tiles
        "expires_at": expires_at,
        "schema_version": "1.0",
    }


@router.get("/preview/{destination_id}")
async def preview_bundle(
    destination_id: str,
    db: AsyncSession = Depends(get_db)
):
    """
    Dashboard preview — authority-viewable bundle (no HMAC needed; for UI).
    Returns the same structure + the generated QR token string.
    """
    destinations = await crud.get_destinations(db, state=None)
    destination = next((d for d in destinations if d["id"] == destination_id), None)
    if not destination:
        raise HTTPException(status_code=404, detail="Destination not found")

    zones = await crud.get_zones(db, destination_id)
    bbox = _compute_bbox(destination, zones)
    expires_at = (
        datetime.datetime.utcnow() + datetime.timedelta(days=7)
    ).isoformat() + "Z"

    return {
        "qr_token": generate_destination_token(destination_id),
        "destination": destination,
        "zones": zones,
        "zone_count": len(zones),
        "tile_bbox": bbox,
        "tile_zoom_range": [10, 16],
        "expires_at": expires_at,
        "schema_version": "1.0",
    }
