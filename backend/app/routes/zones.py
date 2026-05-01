# app/routes/zones.py
import uuid
from typing import List
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud
from app.models import schemas
from app.dependencies import get_current_authority

router = APIRouter()

@router.get("")
async def list_zones(
    destination_id: str = Query(...), 
    db: AsyncSession = Depends(get_db)
):
    """List all active zones for a destination."""
    return await crud.get_zones(db, destination_id)

@router.post("")
async def create_zone(
    body: schemas.ZoneCreate,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Create a new zone (Authority only)."""
    zone_id = str(uuid.uuid4())
    return await crud.create_zone(db, body, authority_id, zone_id)

@router.delete("/{zone_id}")
async def delete_zone(
    zone_id: str,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Deactivate a zone (Authority only)."""
    await crud.delete_zone(db, zone_id, authority_id)
    return {"message": "Zone deactivated"}
