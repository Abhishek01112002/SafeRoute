# app/routes/trips.py
"""
Trip API routes — POST, GET, and lifecycle management.

Trips are the journey/itinerary layer. A Tourist identity is registered once;
Trips are created fresh for each journey and can have multiple stops.
"""
from datetime import datetime
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, field_validator
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.db.session import get_db
from app.dependencies import get_current_tourist
from app.models.trips import Trip, TripStop
from app.logging_config import get_logger

router = APIRouter(prefix="/v3/trips", tags=["trips"])
log = get_logger(__name__)


# ---------------------------------------------------------------------------
# Pydantic schemas (local to trips — keeps schemas.py clean)
# ---------------------------------------------------------------------------

class TripStopCreate(BaseModel):
    destination_id: Optional[str] = None
    name: str
    destination_state: Optional[str] = None
    visit_date_from: datetime
    visit_date_to: datetime
    order_index: int = 1
    center_lat: Optional[float] = None
    center_lng: Optional[float] = None


class TripCreate(BaseModel):
    trip_start_date: datetime
    trip_end_date: datetime
    stops: List[TripStopCreate]
    notes: Optional[str] = None

    @field_validator("trip_end_date")
    @classmethod
    def end_after_start(cls, v: datetime, info) -> datetime:
        start = info.data.get("trip_start_date")
        if start and v <= start:
            raise ValueError("trip_end_date must be after trip_start_date")
        return v

    @field_validator("stops")
    @classmethod
    def at_least_one_stop(cls, v: list) -> list:
        if not v:
            raise ValueError("A trip must have at least one stop")
        return v


def _stop_to_dict(stop: TripStop) -> dict:
    return {
        "stop_id": stop.stop_id,
        "trip_id": stop.trip_id,
        "destination_id": stop.destination_id,
        "name": stop.name,
        "destination_state": stop.destination_state,
        "visit_date_from": stop.visit_date_from.isoformat(),
        "visit_date_to": stop.visit_date_to.isoformat(),
        "order_index": stop.order_index,
        "center_lat": stop.center_lat,
        "center_lng": stop.center_lng,
    }


def _trip_to_dict(trip: Trip) -> dict:
    return {
        "trip_id": trip.trip_id,
        "tourist_id": trip.tourist_id,
        "status": trip.status,
        "trip_start_date": trip.trip_start_date.isoformat(),
        "trip_end_date": trip.trip_end_date.isoformat(),
        "primary_state": trip.primary_state,
        "notes": trip.notes,
        "stops": [_stop_to_dict(s) for s in trip.stops],
        "created_at": trip.created_at.isoformat() if trip.created_at else datetime.now().isoformat(),
    }


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/", summary="Create a new trip")
async def create_trip(
    body: TripCreate,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """
    Create a new trip for the authenticated tourist.
    If any existing ACTIVE trip exists, it is automatically set to COMPLETED
    (a tourist can only have one active trip at a time).
    """
    import uuid

    # Auto-complete any currently ACTIVE trip
    result = await db.execute(
        select(Trip).where(Trip.tourist_id == tourist_id, Trip.status == "ACTIVE")
    )
    active = result.scalars().all()
    for old in active:
        old.status = "COMPLETED"
        log.info("trip.auto_completed", tourist_id=tourist_id, trip_id=old.trip_id)

    # Derive primary_state from first stop
    primary_state = body.stops[0].destination_state if body.stops else None

    new_trip = Trip(
        trip_id=f"TRIP-{uuid.uuid4().hex[:8].upper()}",
        tourist_id=tourist_id,
        status="ACTIVE",
        trip_start_date=body.trip_start_date,
        trip_end_date=body.trip_end_date,
        primary_state=primary_state,
        notes=body.notes,
    )

    for i, stop_in in enumerate(body.stops):
        new_trip.stops.append(TripStop(
            trip_id=new_trip.trip_id,
            destination_id=stop_in.destination_id,
            name=stop_in.name,
            destination_state=stop_in.destination_state,
            visit_date_from=stop_in.visit_date_from,
            visit_date_to=stop_in.visit_date_to,
            order_index=stop_in.order_index or (i + 1),
            center_lat=stop_in.center_lat,
            center_lng=stop_in.center_lng,
        ))

    db.add(new_trip)
    await db.flush()   # assign server-defaults (created_at etc.) without closing tx

    # Build the response dict BEFORE commit — all data is in-memory at this point
    response = {
        "trip_id":        new_trip.trip_id,
        "tourist_id":     new_trip.tourist_id,
        "status":         new_trip.status,
        "trip_start_date": new_trip.trip_start_date.isoformat(),
        "trip_end_date":   new_trip.trip_end_date.isoformat(),
        "primary_state":  new_trip.primary_state,
        "notes":          new_trip.notes,
        "created_at":     new_trip.created_at.isoformat() if new_trip.created_at else datetime.now().isoformat(),
        "stops": [
            {
                "stop_id":           stop.stop_id,
                "trip_id":           stop.trip_id,
                "destination_id":    stop.destination_id,
                "name":              stop.name,
                "destination_state": stop.destination_state,
                "visit_date_from":   stop.visit_date_from.isoformat(),
                "visit_date_to":     stop.visit_date_to.isoformat(),
                "order_index":       stop.order_index,
                "center_lat":        stop.center_lat,
                "center_lng":        stop.center_lng,
            }
            for stop in new_trip.stops
        ],
    }

    await db.commit()  # now safe — we no longer touch the session after this

    log.info("trip.created", tourist_id=tourist_id, trip_id=new_trip.trip_id,
             stops=len(new_trip.stops))
    return response


@router.get("/active", summary="Get current active trip")
async def get_active_trip(
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """
    Returns the tourist's currently ACTIVE trip (with all stops).
    Returns null if no active trip exists — the app falls back to GPS zone detection.
    """
    result = await db.execute(
        select(Trip)
        .options(selectinload(Trip.stops))
        .where(Trip.tourist_id == tourist_id, Trip.status == "ACTIVE")
        .order_by(Trip.created_at.desc())
    )
    trip = result.scalar_one_or_none()

    if not trip:
        return {"active_trip": None}

    return {"active_trip": _trip_to_dict(trip)}


@router.get("/", summary="List all trips for the tourist")
async def list_trips(
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
    limit: int = 20,
    offset: int = 0,
):
    """Returns all trips (history) for the authenticated tourist, newest first."""
    result = await db.execute(
        select(Trip)
        .options(selectinload(Trip.stops))
        .where(Trip.tourist_id == tourist_id)
        .order_by(Trip.created_at.desc())
        .limit(limit)
        .offset(offset)
    )
    trips = result.scalars().all()
    return {"trips": [_trip_to_dict(t) for t in trips]}


@router.put("/{trip_id}/end", summary="End (complete) a trip early")
async def end_trip(
    trip_id: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """Marks a trip as COMPLETED. Use when the tourist finishes their journey."""
    result = await db.execute(
        select(Trip).where(Trip.trip_id == trip_id, Trip.tourist_id == tourist_id)
    )
    trip = result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")

    trip.status = "COMPLETED"
    await db.commit()
    log.info("trip.ended", tourist_id=tourist_id, trip_id=trip_id)
    return {"status": "COMPLETED", "trip_id": trip_id}


@router.delete("/{trip_id}", summary="Cancel a planned trip")
async def cancel_trip(
    trip_id: str,
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """Cancel a PLANNED trip. Cannot cancel an already ACTIVE or COMPLETED trip."""
    result = await db.execute(
        select(Trip).where(Trip.trip_id == trip_id, Trip.tourist_id == tourist_id)
    )
    trip = result.scalar_one_or_none()
    if not trip:
        raise HTTPException(status_code=404, detail="Trip not found")
    if trip.status not in ("PLANNED", "ACTIVE"):
        raise HTTPException(status_code=400, detail=f"Cannot cancel a {trip.status} trip")

    trip.status = "CANCELLED"
    await db.commit()
    return {"status": "CANCELLED", "trip_id": trip_id}
