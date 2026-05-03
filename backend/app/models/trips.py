# app/models/trips.py
"""
Trip Model — separates journey/itinerary from tourist identity.

A Tourist registers ONCE (identity).
They can create many Trips (one per journey).
Each Trip has multiple TripStops (destinations visited in sequence).
"""
import uuid
from datetime import datetime
from typing import List, Optional
from sqlalchemy import String, Boolean, Float, DateTime, ForeignKey, Text, Integer, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.database import Base


class Trip(Base):
    __tablename__ = "trips"

    trip_id: Mapped[str] = mapped_column(
        String(40), primary_key=True, default=lambda: f"TRIP-{uuid.uuid4().hex[:8].upper()}"
    )
    tourist_id: Mapped[str] = mapped_column(
        ForeignKey("tourists.tourist_id", ondelete="CASCADE"), nullable=False, index=True
    )
    # PLANNED → ACTIVE → COMPLETED | CANCELLED
    status: Mapped[str] = mapped_column(String(20), default="PLANNED", index=True)
    trip_start_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    trip_end_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    # Derived from stops — cached for fast SOS context lookup
    primary_state: Mapped[Optional[str]] = mapped_column(String(100))
    notes: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    stops: Mapped[List["TripStop"]] = relationship(
        back_populates="trip", cascade="all, delete-orphan", order_by="TripStop.order_index"
    )


class TripStop(Base):
    __tablename__ = "trip_stops"

    stop_id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    trip_id: Mapped[str] = mapped_column(
        ForeignKey("trips.trip_id", ondelete="CASCADE"), nullable=False, index=True
    )
    destination_id: Mapped[Optional[str]] = mapped_column(String(30))
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    destination_state: Mapped[Optional[str]] = mapped_column(String(100))
    visit_date_from: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    visit_date_to: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    # Order within the trip (1 = first stop, 2 = second, etc.)
    order_index: Mapped[int] = mapped_column(Integer, default=1)
    # Cached lat/lng for quick zone lookup during SOS
    center_lat: Mapped[Optional[float]] = mapped_column(Float)
    center_lng: Mapped[Optional[float]] = mapped_column(Float)

    trip: Mapped["Trip"] = relationship(back_populates="stops")
