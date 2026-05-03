# app/routes/identity.py
"""
Identity verification endpoint.
Allows checking if a document is already registered (duplicate detection)
WITHOUT returning any PII. Public rate-limited endpoint.
"""
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, field_validator
from typing import Optional
from app.services.identity_service import hash_document_number, generate_tuid
from app.core import limiter
import re

router = APIRouter()


class IdentityVerifyRequest(BaseModel):
    document_type: str
    document_number: str
    date_of_birth: Optional[str] = "1970-01-01"
    nationality: Optional[str] = "IN"

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


@router.post("/verify")
@limiter.limit("10/minute")
async def verify_identity(request: Request, payload: IdentityVerifyRequest):
    """
    Check if a document number is already registered.
    Returns only a boolean + TUID (no PII).
    Uses lazy DB import to avoid circular deps.
    """
    from app.db.session import AsyncSessionLocal
    from app.db.crud import get_tourist_by_doc_hash

    doc_hash = hash_document_number(payload.document_number)

    async with AsyncSessionLocal() as db:
        async with db.begin():
            existing = await get_tourist_by_doc_hash(db, doc_hash)

    if existing:
        return {
            "already_registered": True,
            "tuid": existing.get("tuid"),
            # tourist_id NOT returned (internal identifier)
        }

    # Also return the TUID that WOULD be assigned (for pre-computation)
    dob = payload.date_of_birth or "1970-01-01"
    nat = payload.nationality or "IN"
    prospective_tuid = generate_tuid(
        payload.document_type,
        payload.document_number,
        dob,
        nat,
    )

    return {
        "already_registered": False,
        "prospective_tuid": prospective_tuid,
    }
