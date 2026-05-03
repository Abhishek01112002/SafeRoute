# backend/routers/tourists.py

import uuid, hashlib, json, datetime
from fastapi import APIRouter, HTTPException, Security
from pydantic import BaseModel, field_validator
from typing import List, Optional
from backend.database import get_db, save_tourist, load_tourists, get_tourists_paginated
from backend.auth import create_token, require_authority

router = APIRouter(prefix="/tourist", tags=["Tourists"])

@router.get("/")
async def list_tourists(
    page: int = 1,
    page_size: int = 50,
    user: dict = Security(require_authority),
):
    """Authority only: List registered tourists with pagination."""
    return get_tourists_paginated(page=page, page_size=page_size)

_tourists: dict = {}

def _reload():
    global _tourists
    _tourists = load_tourists()

_reload()


class DestinationVisit(BaseModel):
    destination_id:  str
    name:            str
    visit_date_from: str
    visit_date_to:   str


class TouristRegister(BaseModel):
    full_name:               str
    document_type:           str   # AADHAAR | PASSPORT
    document_number:         str
    photo_base64:            str
    blood_group:             str = "Unknown"
    emergency_contact_name:  str
    emergency_contact_phone: str
    trip_start_date:         str
    trip_end_date:           str
    destination_state:       str
    selected_destinations:   List[DestinationVisit] = []

    @field_validator("full_name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("full_name cannot be empty")
        return v


class TouristLogin(BaseModel):
    tourist_id: str


@router.post("/register")
async def register_tourist(body: TouristRegister):
    state_codes = {
        "Uttarakhand": "UK", "Meghalaya": "ML",
        "Arunachal Pradesh": "AR", "Assam": "AS",
    }
    sc  = state_codes.get(body.destination_state, "XX")
    yr  = datetime.datetime.now().year
    tid = f"TID-{yr}-{sc}-{uuid.uuid4().hex[:5].upper()}"

    # Derive config from selected destinations
    config = _derive_config(body.selected_destinations, body.destination_state)

    data = {
        "tourist_id":               tid,
        "full_name":                body.full_name,
        "document_type":            body.document_type,
        "document_number":          body.document_number,
        "photo_base64":             body.photo_base64,
        "blood_group":              body.blood_group,
        "emergency_contact_name":   body.emergency_contact_name,
        "emergency_contact_phone":  body.emergency_contact_phone,
        "trip_start_date":          body.trip_start_date,
        "trip_end_date":            body.trip_end_date,
        "destination_state":        body.destination_state,
        "selected_destinations":    [d.model_dump() for d in body.selected_destinations],
        "qr_data":                  f"SAFEROUTE-{tid}",
        "created_at":               datetime.datetime.now().isoformat(),
        **config,
    }

    save_tourist(tid, data)
    _tourists[tid] = data
    token = create_token(tid, role="tourist")
    return {"tourist": data, "token": token, "expires_in": 86400}


@router.post("/login")
async def login_tourist(body: TouristLogin):
    _reload()
    data = _tourists.get(body.tourist_id)
    if not data:
        raise HTTPException(404, "Tourist not found")
    token = create_token(body.tourist_id, role="tourist")
    return {"tourist": data, "token": token, "expires_in": 86400}


@router.get("/{tourist_id}")
async def get_tourist(tourist_id: str):
    _reload()
    data = _tourists.get(tourist_id)
    if not data:
        raise HTTPException(404, "Tourist not found")
    # Strip sensitive fields for public lookup
    safe = {k: v for k, v in data.items() if k not in ("photo_base64", "document_number")}
    return safe


def _derive_config(selected: List[DestinationVisit], state: str) -> dict:
    defaults = {
        "connectivity_level":   "GOOD",
        "offline_mode_required": False,
        "risk_level":           "LOW",
        "destination_ids":      [],
    }
    if not selected:
        return defaults

    with get_db() as conn:
        ids = [d.destination_id for d in selected]
        placeholders = ",".join("?" * len(ids))
        rows = conn.execute(
            f"SELECT id,connectivity,difficulty FROM destinations WHERE id IN ({placeholders})",
            ids
        ).fetchall()

    if not rows:
        return defaults

    conn_rank  = {"EXCELLENT":5,"GOOD":4,"MODERATE":3,"POOR":2,"VERY_POOR":1,"NONE":0}
    diff_rank  = {"LOW":1,"MODERATE":2,"HIGH":3,"VERY_HIGH":4}

    worst_conn = min(rows, key=lambda r: conn_rank.get(r["connectivity"], 5))
    worst_diff = max(rows, key=lambda r: diff_rank.get(r["difficulty"], 0))

    conn_str = worst_conn["connectivity"]
    return {
        "connectivity_level":   conn_str,
        "offline_mode_required": conn_rank.get(conn_str, 5) <= 2,
        "risk_level":           worst_diff["difficulty"],
        "destination_ids":      [r["id"] for r in rows],
    }
