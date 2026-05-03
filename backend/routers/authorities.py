# backend/routers/authorities.py

import bcrypt, datetime, uuid
from fastapi import APIRouter, HTTPException, Body, Security
from pydantic import BaseModel, field_validator
from typing import Optional
from backend.database import get_db, save_authority, load_authorities
from backend.auth import create_token, require_authority

router = APIRouter(prefix="/auth", tags=["Authority Auth"])

_authorities_cache: dict = {}

def _reload():
    global _authorities_cache
    _authorities_cache = load_authorities()

_reload()

def _safe_view(a: dict) -> dict:
    return {k: v for k, v in a.items() if k != "password"}


class AuthorityRegister(BaseModel):
    full_name:         str
    designation:       str
    department:        str
    badge_id:          str
    district:          str        # jurisdiction scope
    state:             str
    phone:             str
    email:             str
    password:          str

    @field_validator("password")
    @classmethod
    def strong_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        return v

    @field_validator("full_name", "badge_id", "email")
    @classmethod
    def not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Field cannot be empty")
        return v


@router.post("/register/authority")
async def register_authority(body: AuthorityRegister):
    _reload()
    for a in _authorities_cache.values():
        if a["badge_id"] == body.badge_id:
            raise HTTPException(400, "Badge ID already registered")
        if a["email"] == body.email:
            raise HTTPException(400, "Email already registered")

    aid = f"AID-{uuid.uuid4().hex[:8].upper()}"
    hashed = bcrypt.hashpw(body.password.encode(), bcrypt.gensalt()).decode()

    data = {
        "authority_id": aid,
        "full_name":    body.full_name,
        "designation":  body.designation,
        "department":   body.department,
        "badge_id":     body.badge_id,
        "district":     body.district,
        "state":        body.state,
        "phone":        body.phone,
        "email":        body.email,
        "password":     hashed,
        "fcm_token":    None,
        "status":       "active",
        "role":         "authority",
        "created_at":   datetime.datetime.now().isoformat(),
    }
    save_authority(data)
    _authorities_cache[aid] = data
    token = create_token(aid, role="authority")
    return {"authority_id": aid, "token": token, "expires_in": 86400}


@router.post("/login/authority")
async def login_authority(payload: dict = Body(...)):
    email    = (payload.get("email") or "").strip()
    password = payload.get("password") or ""
    if not email or not password:
        raise HTTPException(400, "Email and password required")

    _reload()
    for a in _authorities_cache.values():
        if a["email"] == email:
            if bcrypt.checkpw(password.encode(), a["password"].encode()):
                token = create_token(a["authority_id"], role="authority")
                return {**_safe_view(a), "token": token}
            raise HTTPException(401, "Invalid credentials")
    raise HTTPException(401, "Invalid credentials")


@router.patch("/authority/fcm-token")
async def update_fcm_token(
    payload: dict = Body(...),
    user: dict = Security(require_authority),
):
    """Authority registers their device FCM token for SOS push notifications."""
    fcm_token = payload.get("fcm_token", "").strip()
    if not fcm_token:
        raise HTTPException(400, "fcm_token required")
    with get_db() as conn:
        conn.execute(
            "UPDATE authorities SET fcm_token=? WHERE authority_id=?",
            (fcm_token, user["sub"]),
        )
        conn.commit()
    _reload()
    return {"status": "ok"}
