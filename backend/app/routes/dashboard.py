# app/routes/dashboard.py
"""
Command Center — Authority-only metric and tracking endpoints.
  GET /dashboard/metrics        → real counts for overview cards
  GET /dashboard/tourists       → all registered tourists (list)
  GET /dashboard/locations      → last known location per tourist
"""
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud, sqlite_legacy
from app.dependencies import get_current_authority

router = APIRouter()


@router.get("/metrics")
async def get_metrics(
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """Real-time aggregate counts for the Command Center overview."""
    return await crud.get_dashboard_metrics(db)


@router.get("/tourists")
async def list_tourists(
    limit: int = 50,
    offset: int = 0,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """List all registered tourists with pagination."""
    return await crud.get_tourists_paginated(db, limit=limit, offset=offset)


@router.get("/locations")
async def get_last_locations(
    limit: int = 50,
    offset: int = 0,
    authority_id: str = Depends(get_current_authority)
):
    """
    Returns the most recent location ping for each active tourist.
    The mobile app sends a ping every ~5m of displacement; this gives
    the authority a non-real-time position trail.
    """
    return await crud.get_tourist_last_locations(limit=limit, offset=offset)
