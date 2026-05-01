# app/routes/tourist.py
import uuid
import datetime
import json
import hashlib
from fastapi import APIRouter, HTTPException, Request, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.schemas import TouristRegister, TouristLoginRequest
from app.services.jwt_service import create_jwt_token
from app.services.tourist_config import derive_tourist_config
from app.db import crud
from app.db.session import get_db
from app.core import limiter
from app.config import settings

router = APIRouter()

@router.post("/register")
@limiter.limit("5/minute")
async def register_tourist(request: Request, tourist: TouristRegister, db: AsyncSession = Depends(get_db)):
    state_codes = {
        "Uttarakhand": "UK",
        "Meghalaya": "ML",
        "Arunachal Pradesh": "AR",
        "Assam": "AS",
    }
    state_code = state_codes.get(tourist.destination_state, "XX")
    year = datetime.datetime.now().year
    uid_suffix = uuid.uuid4().hex[:5].upper()
    tourist_id = f"TID-{year}-{state_code}-{uid_suffix}"

    config = derive_tourist_config(tourist.selected_destinations, tourist.destination_state)

    identity_payload = json.dumps({
        "tourist_id": tourist_id,
        "document_type": tourist.document_type,
        "document_number": tourist.document_number,
        "full_name": tourist.full_name,
    }, sort_keys=True)
    blockchain_hash = "0x" + hashlib.sha256(identity_payload.encode()).hexdigest()

    tourist_data = {
        "tourist_id": tourist_id,
        "full_name": tourist.full_name,
        "document_type": tourist.document_type,
        "document_number": tourist.document_number,
        "photo_base64": tourist.photo_base64,
        "emergency_contact_name": tourist.emergency_contact_name,
        "emergency_contact_phone": tourist.emergency_contact_phone,
        "trip_start_date": tourist.trip_start_date,
        "trip_end_date": tourist.trip_end_date,
        "destination_state": tourist.destination_state,
        "selected_destinations": [d.model_dump() for d in tourist.selected_destinations],
        "qr_data": f"SAFEROUTE-{tourist_id}",
        "created_at": datetime.datetime.now().isoformat(),
        "blockchain_hash": blockchain_hash,
        **config,
    }

    tourist_data = await crud.create_tourist(db, tourist, tourist_id, blockchain_hash, config)

    access_token = create_jwt_token(tourist_id)
    refresh_token = create_jwt_token(tourist_id, is_refresh=True)
    
    return {
        "tourist": tourist_data,
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }

@router.post("/login")
async def login_tourist(request: TouristLoginRequest, db: AsyncSession = Depends(get_db)):
    """Login or retrieve tourist data by ID"""
    tourist_data = await crud.get_tourist(db, request.tourist_id)
    if not tourist_data:
        raise HTTPException(status_code=404, detail="Tourist not found")
    
    access_token = create_jwt_token(request.tourist_id)
    refresh_token = create_jwt_token(request.tourist_id, is_refresh=True)
    
    return {
        "tourist": tourist_data,
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }
