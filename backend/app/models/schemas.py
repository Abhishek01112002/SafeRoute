# app/models/schemas.py
from datetime import datetime
from typing import List, Optional
from pydantic import BaseModel, field_validator, EmailStr
import re


class DestinationVisit(BaseModel):
    destination_id: str
    name: str
    visit_date_from: datetime
    visit_date_to: datetime


class TouristRegister(BaseModel):
    full_name: str
    document_type: str  # "AADHAAR", "PASSPORT", "DRIVING_LICENSE"
    document_number: str
    photo_base64: Optional[str] = None         # Legacy: base64 photo
    document_base64: Optional[str] = None      # v3: base64 document scan
    photo_object_key: Optional[str] = None     # v3: MinIO object key
    document_object_key: Optional[str] = None  # v3: MinIO object key for document scan
    emergency_contact_name: Optional[str] = None
    emergency_contact_phone: Optional[str] = None
    trip_start_date: datetime
    trip_end_date: datetime
    destination_state: str
    selected_destinations: List[DestinationVisit] = []
    blood_group: Optional[str] = None
    # --- Identity v3.0 fields ---
    date_of_birth: Optional[str] = "1970-01-01"  # YYYY-MM-DD
    nationality: Optional[str] = "IN"             # ISO 3166-1 alpha-2

    @field_validator("document_type")
    @classmethod
    def validate_document_type(cls, v: str) -> str:
        allowed = {"AADHAAR", "PASSPORT", "DRIVING_LICENSE"}
        if v not in allowed:
            raise ValueError(f"document_type must be one of {allowed}")
        return v

    @field_validator("document_number")
    @classmethod
    def validate_document_number(cls, v: str, info) -> str:
        doc_type = info.data.get("document_type", "")
        v = v.strip()
        if doc_type == "AADHAAR":
            if not re.match(r"^\d{12}$", v):
                raise ValueError("Aadhaar must be exactly 12 digits")
        elif doc_type == "PASSPORT":
            if not re.match(r"^[A-Z0-9]{8,12}$", v.upper()):
                raise ValueError("Passport must be 8-12 alphanumeric characters")
        elif doc_type == "DRIVING_LICENSE":
            clean = v.upper().replace("-", "").replace(" ", "")
            if len(clean) < 10 or len(clean) > 16:
                raise ValueError("Driving license number must be 10-16 characters")
        return v

    @field_validator("date_of_birth")
    @classmethod
    def validate_date_of_birth(cls, v: Optional[str]) -> str:
        if not v:
            return "1970-01-01"
        if not re.match(r"^\d{4}-\d{2}-\d{2}$", v):
            raise ValueError("date_of_birth must be YYYY-MM-DD format")
        return v

    @field_validator("nationality")
    @classmethod
    def validate_nationality(cls, v: Optional[str]) -> str:
        if not v:
            return "IN"
        v = v.upper().strip()
        if not re.match(r"^[A-Z]{2}$", v):
            raise ValueError("nationality must be a 2-letter ISO 3166-1 alpha-2 code")
        return v

    @field_validator("trip_end_date")
    @classmethod
    def validate_trip_dates(cls, v: datetime, info) -> datetime:
        """Validate that trip_end_date > trip_start_date"""
        start_date = info.data.get("trip_start_date")
        if start_date and v <= start_date:
            raise ValueError("trip_end_date must be after trip_start_date")
        return v

    @field_validator("trip_start_date")
    @classmethod
    def validate_trip_start_not_past(cls, v: datetime) -> datetime:
        """Validate trip_start_date is not in the past (date-level check)."""
        now = datetime.now()
        today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
        if v < today_start:
            raise ValueError("trip_start_date cannot be in the past")
        return v

    @field_validator("destination_state")
    @classmethod
    def validate_destination_state(cls, v: str) -> str:
        """Validate state name against known Indian states"""
        valid_states = {
            "Andaman and Nicobar Islands", "Andhra Pradesh", "Arunachal Pradesh",
            "Assam", "Bihar", "Chandigarh", "Chhattisgarh", "Dadra and Nagar Haveli and Daman and Diu",
            "Delhi", "Goa", "Gujarat", "Haryana", "Himachal Pradesh", "Jammu and Kashmir",
            "Jharkhand", "Karnataka", "Kerala", "Ladakh", "Lakshadweep", "Madhya Pradesh",
            "Maharashtra", "Manipur", "Meghalaya", "Mizoram", "Nagaland", "Odisha",
            "Puducherry", "Punjab", "Rajasthan", "Sikkim", "Tamil Nadu", "Telangana",
            "Tripura", "Uttar Pradesh", "Uttarakhand", "West Bengal"
        }
        v = v.strip()
        if v not in valid_states:
            raise ValueError(f"destination_state must be a valid Indian state. Got: {v}")
        return v

    @field_validator("blood_group")
    @classmethod
    def validate_blood_group(cls, v: Optional[str]) -> Optional[str]:
        """Validate blood group format"""
        if not v:
            return None
        valid_blood_groups = {"A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-"}
        v = v.upper().strip()
        if v not in valid_blood_groups:
            raise ValueError(f"blood_group must be one of {valid_blood_groups}")
        return v


class TouristLoginRequest(BaseModel):
    tourist_id: str


class AuthorityRegister(BaseModel):
    full_name: str
    designation: Optional[str] = None
    department: Optional[str] = None
    badge_id: str
    jurisdiction_zone: Optional[str] = None
    phone: Optional[str] = None
    email: str  # Will be validated by EmailStr
    password: str

    @field_validator("full_name", "badge_id")
    @classmethod
    def not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Field cannot be empty")
        return v

    @field_validator("email")
    @classmethod
    def validate_email_format(cls, v: str) -> str:
        """Validate email format"""
        v = v.strip().lower()
        # Simple email validation pattern
        pattern = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
        if not re.match(pattern, v):
            raise ValueError("Invalid email format")
        return v

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        """Validate password strength"""
        if len(v) < 8:
            raise ValueError("password must be at least 8 characters")
        if not any(c.isupper() for c in v):
            raise ValueError("password must contain at least one uppercase letter")
        if not any(c.islower() for c in v):
            raise ValueError("password must contain at least one lowercase letter")
        if not any(c.isdigit() for c in v):
            raise ValueError("password must contain at least one digit")
        if not any(c in "!@#$%^&*()-_=+" for c in v):
            raise ValueError("password must contain at least one special character (!@#$%^&*()-_=+)")
        return v


class LocationPing(BaseModel):
    tourist_id: str
    tuid: Optional[str] = None  # v3 cross-system propagation
    latitude: float
    longitude: float
    speed_kmh: Optional[float] = None
    accuracy_meters: Optional[float] = None
    zone_status: Optional[str] = None
    timestamp: Optional[datetime] = None

    @field_validator("latitude")
    @classmethod
    def validate_latitude(cls, v: float) -> float:
        """Validate latitude is in valid range: -90 to +90"""
        if not (-90 <= v <= 90):
            raise ValueError(f"latitude must be between -90 and +90, got {v}")
        return v

    @field_validator("longitude")
    @classmethod
    def validate_longitude(cls, v: float) -> float:
        """Validate longitude is in valid range: -180 to +180"""
        if not (-180 <= v <= 180):
            raise ValueError(f"longitude must be between -180 and +180, got {v}")
        return v

    @field_validator("speed_kmh")
    @classmethod
    def validate_speed(cls, v: Optional[float]) -> Optional[float]:
        """Speed must be non-negative"""
        if v is not None and v < 0:
            raise ValueError(f"speed_kmh must be >= 0, got {v}")
        return v

    @field_validator("accuracy_meters")
    @classmethod
    def validate_accuracy(cls, v: Optional[float]) -> Optional[float]:
        """Accuracy must be non-negative"""
        if v is not None and v < 0:
            raise ValueError(f"accuracy_meters must be >= 0, got {v}")
        return v


class MediaUploadRequest(BaseModel):
    """Request body for POST /v3/media/upload-url"""
    content_type: str    # e.g. "image/jpeg"
    file_size_bytes: int
    tuid: str

class ZonePoint(BaseModel):
    lat: float
    lng: float

class ZoneCreate(BaseModel):
    destination_id: str
    name:           str
    type:           str   # SAFE | CAUTION | RESTRICTED
    shape:          str = "CIRCLE"
    center_lat:     Optional[float] = None
    center_lng:     Optional[float] = None
    radius_m:       Optional[float] = None
    polygon_points: List[ZonePoint] = []

    @field_validator("type")
    @classmethod
    def validate_zone_type(cls, v: str) -> str:
        """Ensure zone type is uppercase and valid."""
        v = v.strip().upper()
        allowed = {"SAFE", "CAUTION", "RESTRICTED"}
        if v not in allowed:
            raise ValueError(f"type must be one of {allowed}")
        return v

class DestinationBase(BaseModel):
    id: str
    state: str
    name: str
    district: str
    altitude_m: Optional[int] = None
    center_lat: float
    center_lng: float
    category: Optional[str] = None
    difficulty: Optional[str] = None
    connectivity: Optional[str] = None
    best_season: Optional[str] = None
    warnings_json: Optional[str] = None
    authority_id: str
    is_active: bool = True

class MeshSOSSync(BaseModel):
    tourist_id_suffix: str
    latitude: float
    longitude: float
    timestamp: datetime
    signature: str
