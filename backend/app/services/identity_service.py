# app/services/identity_service.py
import hashlib
import re
from app.config import settings

def generate_tuid(doc_type: str, doc_number: str, date_of_birth: str, nationality: str) -> str:
    """
    Generate a deterministic Tourist Unique ID (TUID).
    Algorithm: Double SHA-256 of concatenated identity fields + salt.
    Format: SR-IN-26-XXXXXXXXXXXX (24 chars)
    """
    salt = settings.TUID_SALT
    doc_number = doc_number.strip().upper()
    raw = f"{doc_type}:{doc_number}:{date_of_birth}:{nationality}:{salt}"

    first_hash = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    second_hash = hashlib.sha256(first_hash.encode("utf-8")).hexdigest()

    # Prefix + Year + truncated hash
    year_suffix = "26"  # SafeRoute v3 Launch Year
    nationality_code = nationality[:2].upper()

    # Take 12 chars from hash (48 bits of entropy)
    hash_segment = second_hash[:12].upper()

    return f"SR-{nationality_code}-{year_suffix}-{hash_segment}"

def hash_document_number(doc_number: str) -> str:
    """
    Generate a one-way hash of the document number for de-duplication.
    This allows checking if a document is already registered without storing it.
    """
    salt = settings.DOC_NUMBER_SALT
    raw = f"{doc_number.strip().upper()}:{salt}"
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()

def verify_tuid_format(tuid: str) -> bool:
    """Validate TUID pattern."""
    pattern = r"^SR-[A-Z]{2}-\d{2}-[A-Z0-9]{12}$"
    return bool(re.match(pattern, tuid))

def is_legacy_tourist_id(identifier: str) -> bool:
    """
    Returns True if identifier is a legacy TID-... format tourist_id.
    Authority scan accepts both formats for backward compatibility.
    """
    return identifier.startswith("TID-")

def verify_sos_signature(tuid: str, payload_bytes: bytes, signature_hex: str) -> bool:
    """
    Verify HMAC-SHA256 signature for a BLE SOS packet.
    Truncated signatures (e.g. 8 bytes) are accepted if they match.
    """
    import hmac
    expected = hmac.new(tuid.encode(), payload_bytes, hashlib.sha256).hexdigest()
    if len(signature_hex) < 8:
        return False
    return hmac.compare_digest(expected[:len(signature_hex)], signature_hex)
