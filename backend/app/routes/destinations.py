# app/routes/destinations.py
from typing import List
import json
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud
from app.models import schemas
from app.dependencies import get_current_authority

router = APIRouter()


@router.get("/states")
async def get_states(db: AsyncSession = Depends(get_db)):
    """List all distinct destination states."""
    return await crud.get_states(db)


@router.get("")
async def list_all_destinations(db: AsyncSession = Depends(get_db)):
    """List all destinations."""
    return await crud.get_destinations(db)


@router.post("")
async def create_destination(
    body: schemas.DestinationCreate,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db),
):
    """Create a new destination (Authority only)."""
    return await crud.create_destination(db, body, authority_id)


@router.get("/{dest_id}/detail")
async def get_destination_detail(dest_id: str, db: AsyncSession = Depends(get_db)):
    """
    Return full detail for a specific destination including emergency contacts.
    Used by the mobile app's emergency contact and destination detail screens.
    """
    from sqlalchemy import select
    from app.models.database import Destination, Zone

    result = await db.execute(
        select(Destination).where(Destination.id == dest_id, Destination.is_active == True)
    )
    dest = result.scalar_one_or_none()
    if not dest:
        raise HTTPException(status_code=404, detail="Destination not found")

    # Get associated zones
    zone_result = await db.execute(
        select(Zone).where(Zone.destination_id == dest_id, Zone.is_active == True)
    )
    zones = zone_result.scalars().all()

    warnings = []
    try:
        warnings = json.loads(dest.warnings_json or "[]")
    except Exception:
        pass

    return {
        "id": dest.id,
        "name": dest.name,
        "state": dest.state,
        "district": dest.district,
        "altitude_m": dest.altitude_m,
        "center_lat": dest.center_lat,
        "center_lng": dest.center_lng,
        "category": dest.category,
        "difficulty": dest.difficulty,
        "connectivity": dest.connectivity,
        "best_season": dest.best_season,
        "warnings": warnings,
        "zone_count": len(zones),
        # Emergency contacts are stored as advisory info
        # Future: extract from a dedicated emergency_contacts table
        "emergency_contacts": [
            {"name": "National Emergency Helpline", "phone": "112", "type": "POLICE"},
            {"name": "Mountain Rescue", "phone": "1800-180-0009", "type": "RESCUE"},
            {"name": "Ambulance", "phone": "108", "type": "MEDICAL"},
        ],
    }


@router.get("/{dest_id}/trail-graph")
async def get_trail_graph(dest_id: str, db: AsyncSession = Depends(get_db)):
    """
    Return the trail graph (nodes + edges) for offline pathfinding.
    Returns an empty graph if no trail data exists yet — mobile gracefully falls back to GPS.
    """
    from sqlalchemy import select
    from app.models.database import Destination

    result = await db.execute(
        select(Destination).where(Destination.id == dest_id)
    )
    dest = result.scalar_one_or_none()
    if not dest:
        raise HTTPException(status_code=404, detail="Destination not found")

    # Stub trail graph — to be populated as trail data is collected
    # Mobile pathfinding engine handles empty nodes gracefully
    return {
        "destination_id": dest_id,
        "nodes": [],
        "edges": [],
        "metadata": {
            "version": 1,
            "generated_at": None,
            "coverage": "unavailable",
        },
    }


@router.get("/{state}")
async def get_destinations_by_state(state: str, db: AsyncSession = Depends(get_db)):
    """List all destinations in a given state."""
    return await crud.get_destinations(db, state)


@router.delete("/{dest_id}")
async def deactivate_destination(
    dest_id: str,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db),
):
    """Deactivate a destination (Authority only)."""
    success = await crud.delete_destination(db, dest_id, authority_id)
    if not success:
        raise HTTPException(status_code=404, detail="Destination not found")
    return {"message": "Destination deactivated"}
