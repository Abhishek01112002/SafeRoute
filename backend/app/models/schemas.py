# app/models/schemas.py
"""
Pydantic request/response models — extracted from main.py.
These define the API contract and MUST NOT change during refactor.
"""
import re
import base64
import binascii
from typing import List
from pydantic import BaseModel, Field, field_validator


class DestinationVisit(BaseModel):
    destination_id: str
    name: str
    visit_date_from: str
    visit_date_to: str


class TouristRegister(BaseModel):
    full_name: str
    document_type: str
    document_number: str
    photo_base64: str
    emergency_contact_name: str
    emergency_contact_phone: str
    trip_start_date: str
    trip_end_date: str
    destination_state: str
    blood_group: str = "Unknown"
    selected_destinations: List[DestinationVisit] = Field(default_factory=list)

    @field_validator("full_name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("full_name cannot be empty")
        return v

    @field_validator("document_number")
    @classmethod
    def doc_number_valid(cls, v: str, info) -> str:
        v = v.strip()
        doc_type = info.data.get("document_type")
        if doc_type == "AADHAAR":
            if not re.match(r"^\d{12}$", v):
                raise ValueError("AADHAAR must be exactly 12 digits")
        elif doc_type == "PASSPORT":
            if not re.match(r"^[A-Z0-9]{8,12}$", v):
                raise ValueError("PASSPORT must be 8-12 alphanumeric characters")
        return v

    @field_validator("emergency_contact_phone")
    @classmethod
    def phone_valid(cls, v: str) -> str:
        digits = "".join(c for c in v if c.isdigit())
        if len(digits) < 7:
            raise ValueError("emergency_contact_phone must have at least 7 digits")
        return v

    @field_validator("photo_base64")
    @classmethod
    def photo_not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("photo_base64 is required")
        try:
            decoded = base64.b64decode(v, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError("photo_base64 must be valid base64")
        if len(decoded) > 750_000:
            raise ValueError("photo_base64 exceeds 750KB limit")
        return v


class LocationPing(BaseModel):
    tourist_id: str
    latitude: float
    longitude: float
    speed_kmh: float
    accuracy_meters: float
    timestamp: str
    zone_status: str

    @field_validator("tourist_id")
    @classmethod
    def tourist_must_exist(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("tourist_id is required")
        return v


class AuthorityRegister(BaseModel):
    full_name: str
    designation: str
    department: str
    badge_id: str
    jurisdiction_zone: str
    phone: str
    email: str
    password: str

    @field_validator("full_name", "badge_id", "email")
    @classmethod
    def not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Field cannot be empty")
        return v

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 6:
            raise ValueError("password must be at least 6 characters")
        return v


class TouristLoginRequest(BaseModel):
    tourist_id: str
