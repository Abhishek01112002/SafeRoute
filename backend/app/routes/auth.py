# app/routes/auth.py
import uuid
import datetime
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

@router.post("/register/authority")
@limiter.limit("5/minute")
async def register_authority(request: Request, auth: AuthorityRegister, db: AsyncSession = Depends(get_db)):
    # Duplicate checks using CRUD (respects READ_FROM_PG)
    existing = await crud.get_authority_by_email(db, auth.email)
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")

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
        "password": hashed_pw,
        "status": "active",
        "role": "authority",
        "created_at": datetime.datetime.now().isoformat(),
    }

    await crud.create_authority(db, auth, authority_id, hashed_pw)

    access_token = create_jwt_token(authority_id, role="authority")
    refresh_token = create_jwt_token(authority_id, role="authority", is_refresh=True)

    return {
        "message": "Registration successful. Account activated.",
        "authority_id": authority_id,
        "status": "active",
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }

@router.post("/login/authority")
@limiter.limit("10/minute")
async def login_authority(request: Request, payload: dict = Body(...), db: AsyncSession = Depends(get_db)):
    email = (payload.get("email") or "").strip()
    password = payload.get("password") or ""

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    auth = await crud.get_authority_by_email(db, email)
    if not auth:
        raise HTTPException(status_code=401, detail="Invalid email or password")

    # Handle different field names between legacy (password) and normalized (password_hash)
    stored_hash = auth.get("password_hash") or auth.get("password", "")
    
    if pwd_context.verify(password, stored_hash):
        access_token = create_jwt_token(auth["authority_id"], role="authority")
        refresh_token = create_jwt_token(auth["authority_id"], role="authority", is_refresh=True)
        
        response_data = _safe_authority_view(auth)
        response_data["token"] = access_token
        response_data["refresh_token"] = refresh_token
        response_data["expires_in"] = settings.JWT_ACCESS_EXPIRY_MINUTES * 60
        return response_data
    
    raise HTTPException(status_code=401, detail="Invalid email or password")

@router.post("/refresh")
async def refresh_token(credentials: HTTPAuthorizationCredentials = Security(security)):
    """Refresh JWT token using a Refresh Token"""
    token = credentials.credentials
    payload = verify_jwt_payload(token)
    
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    
    subject_id = payload.get("sub") or payload.get("tourist_id") or payload.get("authority_id")
    role = payload.get("role")
    
    new_access_token = create_jwt_token(subject_id, role=role)
    new_refresh_token = create_jwt_token(subject_id, role=role, is_refresh=True)
    
    return {
        "token": new_access_token,
        "refresh_token": new_refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }
