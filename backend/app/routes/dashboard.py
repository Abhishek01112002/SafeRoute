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
async def list_tourists(authority_id: str = Depends(get_current_authority)):
    """List all registered tourists (name, id, state, dates)."""
    tourists = []
    for tid, data in sqlite_legacy.tourists_db.items():
        tourists.append({
            "tourist_id": tid,
            "full_name": data.get("full_name"),
            "destination_state": data.get("destination_state"),
            "trip_start_date": data.get("trip_start_date"),
            "trip_end_date": data.get("trip_end_date"),
            "selected_destinations": data.get("selected_destinations", []),
            "emergency_contact_phone": data.get("emergency_contact_phone"),
        })
    return tourists


@router.get("/locations")
async def get_last_locations(authority_id: str = Depends(get_current_authority)):
    """
    Returns the most recent location ping for each active tourist.
    The mobile app sends a ping every ~5m of displacement; this gives
    the authority a non-real-time position trail.
    """
    return await crud.get_tourist_last_locations(limit=500)
