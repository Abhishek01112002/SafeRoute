# app/routes/destinations.py
from typing import List
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud

router = APIRouter()

@router.get("/{state}")
async def get_destinations_by_state(state: str, db: AsyncSession = Depends(get_db)):
    """List all destinations in a given state."""
    return await crud.get_destinations(db, state)

@router.get("")
async def list_all_destinations(db: AsyncSession = Depends(get_db)):
    """List all destinations."""
    return await crud.get_destinations(db)
