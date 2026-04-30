# backend/auth.py
# JWT creation, verification, and FastAPI dependency injectors.
# Role hierarchy: tourist < authority < superadmin (future)

import os, datetime
import jwt
from fastapi import HTTPException, Security
from fastapi.security import HTTPBearer, HTTPAuthCredentials
from typing import Optional

_security = HTTPBearer()

def _get_secret() -> str:
    secret = os.getenv("JWT_SECRET")
    if not secret:
        raise RuntimeError(
            "JWT_SECRET environment variable is not set. "
            "Generate one with: python -c \"import secrets; print(secrets.token_hex(32))\""
        )
    return secret

JWT_ALGORITHM  = "HS256"
JWT_EXPIRY_HRS = 24

def create_token(subject_id: str, role: str, expires_hours: int = JWT_EXPIRY_HRS) -> str:
    payload = {
        "sub":  subject_id,
        "role": role,
        "exp":  datetime.datetime.utcnow() + datetime.timedelta(hours=expires_hours),
        "iat":  datetime.datetime.utcnow(),
    }
    return jwt.encode(payload, _get_secret(), algorithm=JWT_ALGORITHM)

def decode_token(token: str) -> Optional[dict]:
    try:
        return jwt.decode(token, _get_secret(), algorithms=[JWT_ALGORITHM])
    except jwt.ExpiredSignatureError:
        return None
    except jwt.InvalidTokenError:
        return None

# ── FastAPI dependencies ──────────────────────────────────────────────────────

async def get_current_user(
    credentials: HTTPAuthCredentials = Security(_security),
) -> dict:
    """Returns {"sub": id, "role": "tourist"|"authority"}. Raises 401 if invalid."""
    payload = decode_token(credentials.credentials)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return payload

async def require_tourist(user: dict = Security(get_current_user)) -> str:
    """Returns tourist_id. Accepts both tourist and authority tokens."""
    return user["sub"]

async def require_authority(user: dict = Security(get_current_user)) -> dict:
    """Returns full payload. Rejects non-authority tokens."""
    if user.get("role") != "authority":
        raise HTTPException(status_code=403, detail="Authority role required")
    return user
