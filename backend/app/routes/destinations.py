# app/routes/destinations.py
from typing import List
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud

router = APIRouter()

VALID_STATES = {"Uttarakhand", "Meghalaya", "Arunachal Pradesh", "Assam"}

@router.get("/states")
async def get_available_states():
    """List all available states for the dropdown."""
    return sorted(list(VALID_STATES))

@router.get("/{state}")
async def get_destinations_by_state(state: str, db: AsyncSession = Depends(get_db)):
    """List all destinations in a given state."""
    if state not in VALID_STATES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid state: {state}. Must be one of {VALID_STATES}",
        )
    return await crud.get_destinations(db, state)

@router.get("")
async def list_all_destinations(db: AsyncSession = Depends(get_db)):
    """List all destinations."""
    return await crud.get_destinations(db)
