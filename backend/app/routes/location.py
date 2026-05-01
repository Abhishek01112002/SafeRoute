# app/routes/location.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.schemas import LocationPing
from app.dependencies import get_current_tourist
from app.db import sqlite_legacy, crud
from app.db.session import get_db

router = APIRouter()

@router.post("/ping")
async def receive_ping(ping: LocationPing, tourist_id: str = Depends(get_current_tourist), db: AsyncSession = Depends(get_db)):
    # JWT already validated by Depends, but verify it matches the ping
    if ping.tourist_id != tourist_id:
        raise HTTPException(status_code=403, detail="Tourist ID mismatch")
    
    # Validate tourist exists
    if ping.tourist_id not in sqlite_legacy.tourists_db:
        raise HTTPException(status_code=404, detail="Tourist ID not registered")

    # deque automatically drops oldest entries
    sqlite_legacy.location_logs.append(ping.model_dump())
    
    # Save to PG
    await crud.create_location_ping(db, ping)
    return {"status": "received"}
