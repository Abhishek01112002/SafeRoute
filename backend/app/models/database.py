# app/models/database.py
from datetime import datetime
from typing import List, Optional
from sqlalchemy import String, Boolean, Float, DateTime, ForeignKey, Text, BigInteger, Integer, func, Index, UniqueConstraint
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
    # TRIP FIELDS: Legacy — new tourists use the Trip model instead.
    # Kept nullable for backward compatibility with existing tourist records.
    trip_start_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    trip_end_date: Mapped[Optional[datetime]] = mapped_column(DateTime, nullable=True)
    destination_state: Mapped[Optional[str]] = mapped_column(String(100), nullable=True, index=True)
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
    __table_args__ = (
        UniqueConstraint("tourist_id", "idempotency_key", name="uq_sos_tourist_idempotency"),
        Index("ix_sos_incident_status", "incident_status"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    tuid: Mapped[Optional[str]] = mapped_column(String(24), index=True)  # v3 cross-system
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(30), default="MANUAL")
    source: Mapped[str] = mapped_column(String(20), default="DIRECT")
    incident_status: Mapped[str] = mapped_column(String(30), default="ACTIVE")
    delivery_state: Mapped[str] = mapped_column(String(30), default="PENDING")
    dispatch_status: Mapped[str] = mapped_column(String(30), default="queued")
    delivery_summary: Mapped[Optional[str]] = mapped_column(Text)
    group_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("tourist_groups.group_id"), index=True)
    relayed_by_tourist_id: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    correlation_id: Mapped[Optional[str]] = mapped_column(String(50))
    # Accept client timestamp when available (no server_default)
    timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    is_synced: Mapped[bool] = mapped_column(Boolean, default=False)
    acknowledged_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    acknowledged_by: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    authority_response: Mapped[Optional[str]] = mapped_column(Text)
    resolved_at: Mapped[Optional[datetime]] = mapped_column(DateTime)

    tourist: Mapped["Tourist"] = relationship(back_populates="sos_events")

class SOSDispatchQueue(Base):
    __tablename__ = "sos_dispatch_queue"
    __table_args__ = (
        Index("ix_sos_queue_due", "state", "next_attempt_at"),
        Index("ix_sos_queue_event", "sos_event_id"),
    )

    queue_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sos_event_id: Mapped[int] = mapped_column(ForeignKey("sos_events.id", ondelete="CASCADE"), nullable=False)
    tourist_id: Mapped[str] = mapped_column(String(30), index=True, nullable=False)
    tuid: Mapped[Optional[str]] = mapped_column(String(24), index=True)
    idempotency_key: Mapped[Optional[str]] = mapped_column(String(80), index=True)
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    trigger_type: Mapped[str] = mapped_column(String(30), default="MANUAL")
    state: Mapped[str] = mapped_column(String(30), default="PENDING", index=True)
    attempt_count: Mapped[int] = mapped_column(Integer, default=0)
    next_attempt_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    ttl_expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False)
    delivered_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    escalated_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    last_error: Mapped[Optional[str]] = mapped_column(Text)
    claimed_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    sos_event: Mapped["SOSEvent"] = relationship()

class SOSDeliveryAudit(Base):
    __tablename__ = "sos_delivery_audit"
    __table_args__ = (
        Index("ix_sos_audit_event", "sos_event_id", "timestamp"),
    )

    audit_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    sos_event_id: Mapped[int] = mapped_column(ForeignKey("sos_events.id", ondelete="CASCADE"), nullable=False)
    queue_id: Mapped[Optional[str]] = mapped_column(String(36), ForeignKey("sos_dispatch_queue.queue_id"))
    channel: Mapped[str] = mapped_column(String(30), nullable=False)
    target: Mapped[Optional[str]] = mapped_column(String(255))
    status: Mapped[str] = mapped_column(String(30), nullable=False)
    provider_status: Mapped[Optional[str]] = mapped_column(String(80))
    error_message: Mapped[Optional[str]] = mapped_column(Text)
    attempt_number: Mapped[int] = mapped_column(Integer, default=0)
    timestamp: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)

class SOSProviderCircuit(Base):
    __tablename__ = "sos_provider_circuit"

    provider: Mapped[str] = mapped_column(String(40), primary_key=True)
    state: Mapped[str] = mapped_column(String(20), default="CLOSED")
    failure_count: Mapped[int] = mapped_column(Integer, default=0)
    opened_until: Mapped[Optional[datetime]] = mapped_column(DateTime)
    last_failure_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    last_success_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

class TouristMeshKey(Base):
    __tablename__ = "tourist_mesh_keys"
    __table_args__ = (
        UniqueConstraint("tourist_id", "key_version", name="uq_mesh_key_tourist_version"),
        Index("ix_mesh_key_tuid_suffix", "tuid_suffix"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    tuid: Mapped[str] = mapped_column(String(24), index=True)
    tuid_suffix: Mapped[str] = mapped_column(String(4), index=True)
    key_version: Mapped[int] = mapped_column(Integer, default=1)
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE")
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    revoked_at: Mapped[Optional[datetime]] = mapped_column(DateTime)
    grace_expires_at: Mapped[Optional[datetime]] = mapped_column(DateTime)

class AuthorityDevice(Base):
    __tablename__ = "authority_devices"
    __table_args__ = (
        UniqueConstraint("authority_id", "fcm_token", name="uq_authority_device_token"),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    authority_id: Mapped[str] = mapped_column(ForeignKey("authorities.authority_id", ondelete="CASCADE"), index=True)
    fcm_token: Mapped[str] = mapped_column(Text, nullable=False)
    platform: Mapped[Optional[str]] = mapped_column(String(30))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now())
    last_seen_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

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

class TouristGroup(Base):
    __tablename__ = "tourist_groups"

    group_id: Mapped[str] = mapped_column(String(36), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    invite_code: Mapped[str] = mapped_column(String(6), unique=True, nullable=False, index=True)
    invite_expires_at: Mapped[datetime] = mapped_column(DateTime, nullable=False, index=True)
    trip_id: Mapped[Optional[str]] = mapped_column(String(36), index=True)
    destination_id: Mapped[Optional[str]] = mapped_column(String(50), index=True)
    created_by_tourist_id: Mapped[str] = mapped_column(
        ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE", index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), onupdate=func.now())

    members: Mapped[List["TouristGroupMember"]] = relationship(back_populates="group", cascade="all, delete-orphan")
    snapshots: Mapped[List["TouristGroupLocationSnapshot"]] = relationship(back_populates="group", cascade="all, delete-orphan")
    events: Mapped[List["TouristGroupEvent"]] = relationship(back_populates="group", cascade="all, delete-orphan")

class TouristGroupMember(Base):
    __tablename__ = "tourist_group_members"
    __table_args__ = (
        UniqueConstraint("group_id", "tourist_id", name="uq_group_member"),
        Index("ix_group_member_active", "tourist_id", "left_at"),
    )

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    group_id: Mapped[str] = mapped_column(ForeignKey("tourist_groups.group_id", ondelete="CASCADE"), index=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), index=True)
    tuid: Mapped[Optional[str]] = mapped_column(String(24), index=True)
    display_name: Mapped[str] = mapped_column(String(80), nullable=False)
    role: Mapped[str] = mapped_column(String(20), default="MEMBER")
    sharing_status: Mapped[str] = mapped_column(String(20), default="SHARING", index=True)
    joined_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)
    left_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    last_seen_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)

    group: Mapped["TouristGroup"] = relationship(back_populates="members")
    tourist: Mapped["Tourist"] = relationship()

class TouristGroupLocationSnapshot(Base):
    __tablename__ = "tourist_group_location_snapshots"

    group_id: Mapped[str] = mapped_column(ForeignKey("tourist_groups.group_id", ondelete="CASCADE"), primary_key=True)
    tourist_id: Mapped[str] = mapped_column(ForeignKey("tourists.tourist_id", ondelete="CASCADE"), primary_key=True)
    latitude: Mapped[Optional[float]] = mapped_column(Float)
    longitude: Mapped[Optional[float]] = mapped_column(Float)
    accuracy_meters: Mapped[Optional[float]] = mapped_column(Float)
    battery_level: Mapped[Optional[float]] = mapped_column(Float)
    zone_status: Mapped[Optional[str]] = mapped_column(String(20))
    source: Mapped[str] = mapped_column(String(20), default="websocket")
    trust_level: Mapped[str] = mapped_column(String(20), default="confirmed")
    client_timestamp: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True)
    server_updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)

    group: Mapped["TouristGroup"] = relationship(back_populates="snapshots")

class TouristGroupEvent(Base):
    __tablename__ = "tourist_group_events"

    id: Mapped[int] = mapped_column(primary_key=True, autoincrement=True)
    group_id: Mapped[str] = mapped_column(ForeignKey("tourist_groups.group_id", ondelete="CASCADE"), index=True)
    tourist_id: Mapped[Optional[str]] = mapped_column(String(30), index=True)
    event_type: Mapped[str] = mapped_column(String(40), index=True)
    source: Mapped[str] = mapped_column(String(20), default="server")
    trust_level: Mapped[str] = mapped_column(String(20), default="confirmed")
    payload_json: Mapped[Optional[str]] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=func.now(), index=True)

    group: Mapped["TouristGroup"] = relationship(back_populates="events")

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
