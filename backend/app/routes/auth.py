# app/routes/auth.py
import uuid
import datetime
import time
import re
from fastapi import APIRouter, Depends, HTTPException, Security, Body, Request
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.schemas import AuthorityRegister
from app.services.jwt_service import create_jwt_token, verify_jwt_payload
from app.dependencies import security
from app.db import sqlite_legacy, crud
from app.db.session import get_db
from app.core import pwd_context, limiter
from app.config import settings

router = APIRouter()

def _safe_authority_view(auth: dict) -> dict:
    """Return authority dict without the hashed password."""
    return {k: v for k, v in auth.items() if k != "password"}

# Password strength requirements
MIN_PASSWORD_LENGTH = 12
PASSWORD_REGEX = r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[@$!%*?&])[A-Za-z\d@$!%*?&]{12,}$"

@router.post("/register/authority")
@limiter.limit("5/minute")
async def register_authority(request: Request, auth: AuthorityRegister, db: AsyncSession = Depends(get_db)):
    """Register new authority with immediate activation."""
    # Email format validation
    if not re.match(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$", auth.email):
        raise HTTPException(status_code=400, detail="Invalid email format")

    # Password strength validation
    if len(auth.password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(
            status_code=400,
            detail=f"Password must be at least {MIN_PASSWORD_LENGTH} characters"
        )
    if not re.match(PASSWORD_REGEX, auth.password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain uppercase, lowercase, number, and special character (@$!%*?&)"
        )

    # Duplicate checks using CRUD (respects READ_FROM_PG)
    existing = await crud.get_authority_by_email(db, auth.email)
    if existing:
        # Return generic error to prevent email enumeration
        raise HTTPException(status_code=409, detail="Registration failed. Please contact administrator.")

    # Check badge_id uniqueness if provided
    if auth.badge_id:
        existing_badge = await crud.get_authority_by_badge(db, auth.badge_id)
        if existing_badge:
            raise HTTPException(status_code=409, detail="Badge ID already registered")

    authority_id = f"AID-{uuid.uuid4().hex[:8].upper()}"
    hashed_pw = pwd_context.hash(auth.password)

    auth_data = {
        "authority_id": authority_id,
        "full_name": auth.full_name,
        "designation": auth.designation,
        "department": auth.department,
        "badge_id": auth.badge_id,
        "jurisdiction_zone": auth.jurisdiction_zone,
        "phone": auth.phone,
        "email": auth.email,
        "password_hash": hashed_pw,
        "status": "active",  # Direct activation - no approval needed
        "role": "authority",
        "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "last_login": None,
        "failed_login_attempts": 0,
        "email_verified": True,  # Auto-verified for now
    }

    await crud.create_authority(db, auth_data)

    # Auto-login after registration
    access_token = create_jwt_token(authority_id, role="authority")
    refresh_token = create_jwt_token(authority_id, role="authority", is_refresh=True)

    return {
        "message": "Registration successful. Welcome to SafeRoute Authority Hub.",
        "authority_id": authority_id,
        "status": "active",
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }

@router.post("/login/authority")
@limiter.limit("5/minute")  # Reduced for security
async def login_authority(request: Request, payload: dict = Body(...), db: AsyncSession = Depends(get_db)):
    """Authority login with account status verification."""
    email = (payload.get("email") or "").strip()
    password = payload.get("password") or ""

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    # Rate limiting is handled by @limiter decorator

    auth = await crud.get_authority_by_email(db, email)
    if not auth:
        # Generic error to prevent email enumeration
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Check account status
    status = auth.get("status", "active")
    if status == "suspended":
        raise HTTPException(
            status_code=403,
            detail="Account suspended. Contact system administrator."
        )
    if status == "inactive":
        raise HTTPException(
            status_code=403,
            detail="Account deactivated. Contact system administrator."
        )

    # Verify password
    stored_hash = auth.get("password_hash") or auth.get("password", "")
    if not pwd_context.verify(password, stored_hash):
        # Increment failed login attempts
        await crud.increment_authority_failed_logins(db, auth["authority_id"])
        raise HTTPException(status_code=401, detail="Invalid credentials")

    # Successful login - reset failed attempts and update last_login
    await crud.reset_authority_failed_logins(db, auth["authority_id"])

    # Generate tokens
    access_token = create_jwt_token(auth["authority_id"], role="authority")
    refresh_token = create_jwt_token(auth["authority_id"], role="authority", is_refresh=True)

    response_data = _safe_authority_view(auth)
    response_data["token"] = access_token
    response_data["refresh_token"] = refresh_token
    response_data["expires_in"] = settings.JWT_ACCESS_EXPIRY_MINUTES * 60
    response_data["last_login"] = datetime.datetime.now(datetime.timezone.utc).isoformat()

    return response_data

@router.post("/refresh")
async def refresh_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Refresh JWT token using a Refresh Token"""
    token = credentials.credentials
    payload = verify_jwt_payload(token)

    # Validate token structure
    if not token or not token.strip():
        raise HTTPException(status_code=401, detail="Empty token")

    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    # Check if refresh token is expired (exp is unix seconds)
    token_expiry = payload.get("exp")
    current_time = int(time.time())
    if token_expiry and token_expiry < current_time:
        raise HTTPException(status_code=401, detail="Refresh token has expired")

    subject_id = payload.get("sub") or payload.get("tourist_id") or payload.get("authority_id")
    if not subject_id:
        raise HTTPException(status_code=401, detail="Invalid token subject")
    role = payload.get("role")

    new_access_token = create_jwt_token(subject_id, role=role)
    new_refresh_token = create_jwt_token(subject_id, role=role, is_refresh=True)

    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }
