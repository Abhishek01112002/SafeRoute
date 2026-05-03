# app/models/database.py
from datetime import datetime
from typing import List, Optional
from sqlalchemy import String, Boolean, Float, DateTime, ForeignKey, Text, BigInteger, func, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship

class Base(DeclarativeBase):
    """Base class for all ORM models."""
    pass

class Tourist(Base):
    __tablename__ = "tourists"

    tourist_id: Mapped[str] = mapped_column(String(30), primary_key=True)
    # --- Identity v3.0 fields ---
    tuid: Mapped[Optional[str]] = mapped_column(String(24), unique=True, index=True)
    document_number_hash: Mapped[Optional[str]] = mapped_column(Text, index=True)
    date_of_birth: Mapped[str] = mapped_column(String(10), default="1970-01-01")
    nationality: Mapped[str] = mapped_column(String(2), default="IN")
    migrated_from_legacy: Mapped[bool] = mapped_column(Boolean, default=False)
    # --- Core fields ---
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    document_type: Mapped[str] = mapped_column(String(20), nullable=False)
    # document_number column dropped — use document_number_hash for de-duplication
    photo_url: Mapped[Optional[str]] = mapped_column(Text)         # Legacy disk URL
    photo_object_key: Mapped[Optional[str]] = mapped_column(Text)  # MinIO object key (v3)
    document_object_key: Mapped[Optional[str]] = mapped_column(Text) # MinIO doc scan (v3)
    photo_base64_legacy: Mapped[Optional[str]] = mapped_column(Text)  # Kept for migration
    emergency_contact_name: Mapped[Optional[str]] = mapped_column(String(255))
    emergency_contact_phone: Mapped[Optional[str]] = mapped_column(String(30))
    trip_start_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    trip_end_date: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    destination_state: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    qr_data: Mapped[Optional[str]] = mapped_column(Text)            # RS256 JWT (v3) or legacy string
    connectivity_level: Mapped[str] = mapped_column(String(20), default="GOOD")
    offline_mode_required: Mapped[bool] = mapped_column(Boolean, default=False)
    risk_level: Mapped[str] = mapped_column(String(20), default="LOW")
    blood_group: Mapped[Optional[str]] = mapped_column(String(10))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    # Relationships
    destinations: Mapped[List["TouristDestination"]] = relationship(back_populates="tourist", cascade="all, delete-orphan")
    sos_events: Mapped[List["SOSEvent"]] = relationship(back_populates="tourist")
    pings: Mapped[List["LocationPing"]] = relationship(back_populates="tourist")
    scan_logs: Mapped[List["AuthorityScanLog"]] = relationship(back_populates="tourist")
    emergency_contacts: Mapped[List["EmergencyContact"]] = relationship(back_populates="tourist")

class TouristDestination(Base):
    __tablename__ = "tourist_destinations"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    destination_id: Mapped[str] = mapped_column(String(30), nullable=False)
    name: Mapped[str] = mapped_column(String(255))
    visit_date_from: Mapped[datetime] = mapped_column(DateTime)
    visit_date_to: Mapped[datetime] = mapped_column(DateTime)

    tourist: Mapped["Tourist"] = relationship(back_populates="destinations")

class Authority(Base):
    __tablename__ = "authorities"

    authority_id: Mapped[str] = mapped_column(String(30), primary_key=True)
    full_name: Mapped[str] = mapped_column(String(255), nullable=False)
    designation: Mapped[Optional[str]] = mapped_column(String(100))
    department: Mapped[Optional[str]] = mapped_column(String(100))
    badge_id: Mapped[str] = mapped_column(String(50), unique=True, nullable=False, index=True)
    jurisdiction_zone: Mapped[Optional[str]] = mapped_column(String(100))
    phone: Mapped[Optional[str]] = mapped_column(String(30))
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    email_verified: Mapped[bool] = mapped_column(Boolean, default=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="active")  # active, suspended, inactive
    role: Mapped[str] = mapped_column(String(20), default="authority")
    failed_login_attempts: Mapped[int] = mapped_column(BigInteger, default=0)
    last_login: Mapped[Optional[datetime]] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())

class SOSEvent(Base):
    __tablename__ = "sos_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    tuid: Mapped[Optional[str]] = mapped_column(String(24), index=True)  # v3 cross-system
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(30), default="MANUAL")
    dispatch_status: Mapped[str] = mapped_column(String(30), default="not_configured")
    correlation_id: Mapped[Optional[str]] = mapped_column(String(50))
    # Accept client timestamp when available (no server_default)
    timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    is_synced: Mapped[bool] = mapped_column(Boolean, default=False)

    tourist: Mapped["Tourist"] = relationship(back_populates="sos_events")

class LocationPing(Base):
    __tablename__ = "location_pings"

    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    tuid: Mapped[Optional[str]] = mapped_column(String(24), index=True)  # v3 cross-system
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    speed_kmh: Mapped[Optional[float]] = mapped_column(Float)
    accuracy_meters: Mapped[Optional[float]] = mapped_column(Float)
    zone_status: Mapped[Optional[str]] = mapped_column(String(20))
    # Accept client timestamp when available (no server_default)
    timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)

    tourist: Mapped["Tourist"] = relationship(back_populates="pings")

class AuthorityScanLog(Base):
    """Audit trail for every authority QR scan. Required for legal compliance."""
    __tablename__ = "authority_scan_log"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)  # UUID v4
    authority_id: Mapped[str] = mapped_column(
        ForeignKey("authorities.authority_id"), index=True, nullable=False
    )
    scanned_tuid: Mapped[str] = mapped_column(String(24), index=True, nullable=False)
    tourist_id: Mapped[Optional[str]] = mapped_column(String(30), ForeignKey("tourists.tourist_id"))
    scanned_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    ip_address: Mapped[Optional[str]] = mapped_column(String(45))
    user_agent: Mapped[Optional[str]] = mapped_column(Text)
    photo_url_generated: Mapped[bool] = mapped_column(Boolean, default=False)

    tourist: Mapped[Optional["Tourist"]] = relationship(back_populates="scan_logs")

class Destination(Base):
    __tablename__ = "destinations"

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    state: Mapped[str] = mapped_column(String(100), index=True)
    name: Mapped[str] = mapped_column(String(255))
    district: Mapped[str] = mapped_column(String(100))
    altitude_m: Mapped[Optional[int]] = mapped_column(BigInteger)
    center_lat: Mapped[float] = mapped_column(Float)
    center_lng: Mapped[float] = mapped_column(Float)
    category: Mapped[Optional[str]] = mapped_column(String(100))
    difficulty: Mapped[Optional[str]] = mapped_column(String(20))
    connectivity: Mapped[Optional[str]] = mapped_column(String(20))
    best_season: Mapped[Optional[str]] = mapped_column(String(100))
    warnings_json: Mapped[Optional[str]] = mapped_column(Text)
    authority_id: Mapped[str] = mapped_column(String(30), index=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

class EmergencyContact(Base):
    __tablename__ = "emergency_contacts"

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    destination_id: Mapped[Optional[str]] = mapped_column(String(50), index=True)
    tourist_id: Mapped[Optional[str]] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    label: Mapped[str] = mapped_column(String(100))
    phone: Mapped[str] = mapped_column(String(30))
    notes: Mapped[Optional[str]] = mapped_column(String(255))

    tourist: Mapped[Optional["Tourist"]] = relationship(back_populates="emergency_contacts")

class Zone(Base):
    __tablename__ = "zones"

    id: Mapped[str] = mapped_column(String(50), primary_key=True)
    destination_id: Mapped[str] = mapped_column(String(50), index=True)
    authority_id: Mapped[str] = mapped_column(String(30), index=True)
    name: Mapped[str] = mapped_column(String(255))
    type: Mapped[str] = mapped_column(String(20)) # SAFE, CAUTION, RESTRICTED
    shape: Mapped[str] = mapped_column(String(20), default="CIRCLE")
    center_lat: Mapped[Optional[float]] = mapped_column(Float)
    center_lng: Mapped[Optional[float]] = mapped_column(Float)
    radius_m: Mapped[Optional[float]] = mapped_column(Float)
    polygon_json: Mapped[Optional[str]] = mapped_column(Text)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())
