# app/routes/tourist.py
import uuid
import datetime
import json
import hashlib
import os
import re
from typing import List, Optional
from fastapi import APIRouter, HTTPException, Request, Depends, File, UploadFile, Form
from fastapi.encoders import jsonable_encoder
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.schemas import TouristRegister, TouristLoginRequest, DestinationVisit
from app.services.jwt_service import create_jwt_token
from app.services.tourist_config import derive_tourist_config
from app.services.identity_service import generate_tuid, hash_document_number
from app.db import crud
from app.db.session import get_db
from app.core import limiter
from app.config import settings
from app.dependencies import get_current_tourist
from app.logging_config import logger, get_logger

log = get_logger("tourist")

# Brute-force protection storage (Redis in production, dict in dev)
_login_attempts: dict = {}  # {tourist_id: [timestamp1, timestamp2, ...]}
MAX_LOGIN_ATTEMPTS = 5
LOGIN_WINDOW_SECONDS = 300  # 5 minutes
LOCKOUT_SECONDS = 900  # 15 minutes

def _check_brute_force(tourist_id: str) -> bool:
    """Check if tourist_id is locked out due to too many failed attempts."""
    now = datetime.datetime.now()
    attempts = _login_attempts.get(tourist_id, [])

    # Clean old attempts outside the window
    attempts = [t for t in attempts if (now - t).total_seconds() < LOGIN_WINDOW_SECONDS]
    _login_attempts[tourist_id] = attempts

    # Check for active lockout
    if len(attempts) >= MAX_LOGIN_ATTEMPTS:
        last_attempt = attempts[-1]
        if (now - last_attempt).total_seconds() < LOCKOUT_SECONDS:
            return False  # Locked out
        # Window passed, reset
        _login_attempts[tourist_id] = []

    return True  # Not locked out

def _record_failed_login(tourist_id: str):
    """Record a failed login attempt."""
    now = datetime.datetime.now()
    if tourist_id not in _login_attempts:
        _login_attempts[tourist_id] = []
    _login_attempts[tourist_id].append(now)

router = APIRouter()

# QR service loaded lazily to avoid import errors when keys are missing
def _get_qr_service():
    from app.services.qr_service import QRService
    return QRService()


@router.post(
    "/register",
    responses={
        429: {
            "description": "Rate limit exceeded",
            "content": {
                "application/json": {
                    "example": {"error": "Rate limit exceeded: 5 per 1 minute"}
                }
            }
        }
    }
)
@limiter.limit("5/minute")
async def register_tourist(
    request: Request,
    tourist: TouristRegister,
    db: AsyncSession = Depends(get_db),
):
    """Register a new tourist — v3 with TUID + RS256 QR JWT."""
    state_codes = {
        "Uttarakhand": "UK",
        "Meghalaya": "ML",
        "Arunachal Pradesh": "AR",
        "Assam": "AS",
    }
    state_code = state_codes.get(tourist.destination_state, "XX")
    year = datetime.datetime.now().year
    uid_suffix = uuid.uuid4().hex[:5].upper()
    tourist_id = f"TID-{year}-{state_code}-{uid_suffix}"

    # --- Identity v3: TUID + Document Hash ---
    dob = tourist.date_of_birth or "1970-01-01"
    nationality = tourist.nationality or "IN"
    tuid = generate_tuid(tourist.document_type, tourist.document_number, dob, nationality)
    doc_hash = hash_document_number(tourist.document_number)
    cid = getattr(request.state, "correlation_id", "-")
    log.info(
        "tourist.register.received",
        destination_state=tourist.destination_state,
        selected_destinations=len(tourist.selected_destinations),
        document_type=tourist.document_type,
    )

    # Duplicate document check (same hash = already registered)
    existing = await crud.get_tourist_by_doc_hash(db, doc_hash)
    if existing:
        raise HTTPException(
            status_code=409,
            detail={
                "error": "Document already registered",
                "tuid": existing.get("tuid"),
                "tourist_id": existing.get("tourist_id"),
            }
        )

    # --- Derive connectivity/risk config ---
    config = derive_tourist_config(tourist.selected_destinations, tourist.destination_state)

    # --- Sign QR JWT ---
    qr_jwt = None
    try:
        qr_service = _get_qr_service()
        qr_jwt = qr_service.sign_qr_jwt(tuid, tourist.full_name, nationality)
    except Exception as e:
        # Graceful fallback: use legacy QR string if signing fails (dev mode)
        print(f"QR JWT signing failed (key missing?): {e}")

    # --- Persist to DB ---
    tourist_data = await crud.create_tourist(
        db,
        tourist,
        tourist_id,
        config,
        tuid=tuid,
        document_number_hash=doc_hash,
        qr_jwt=qr_jwt,
    )
    log.info(
        "tourist.register.db_write",
        tourist_id=tourist_id,
        tuid=tuid,
        cid=cid,
    )

    # --- Issue auth tokens ---
    access_token = create_jwt_token(tourist_id)
    refresh_token = create_jwt_token(tourist_id, is_refresh=True)

    return {
        "tourist": tourist_data,
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }


@router.get("/photo/{tourist_id}")
async def get_tourist_photo(
    tourist_id: str,
    tourist: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """Serve uploaded profile photo for a tourist.
    Returns the photo file from local filesystem or 404.
    """
    from fastapi.responses import FileResponse

    tourist_data = await crud.get_tourist(db, tourist_id)
    if not tourist_data:
        raise HTTPException(status_code=404, detail="Tourist not found")

    photo_key = tourist_data.get("photo_object_key", "")
    if not photo_key:
        raise HTTPException(status_code=404, detail="No photo on file")

    # Check if file exists on local filesystem
    if os.path.exists(photo_key):
        return FileResponse(photo_key, media_type="image/jpeg")

    raise HTTPException(status_code=404, detail="Photo file not found on server")

MAX_PHOTO_SIZE = 5 * 1024 * 1024
MAX_DOC_SIZE = 10 * 1024 * 1024

async def validate_file(file: UploadFile, max_size: int, allowed_mimes: list):
    """Secure file validation for size and MIME type."""
    # Note: in a real FastAPI request, file.size is available if using newer versions
    # or you can read a chunk to check size.
    content = await file.read(1) # Peak
    await file.seek(0)

    # We'll use the file.size if available (FastAPI 0.100+)
    # For now, let's assume it's there.
    if hasattr(file, 'size') and file.size and file.size > max_size:
        raise HTTPException(status_code=413, detail=f"{file.filename} too large")

    if file.content_type not in allowed_mimes:
        raise HTTPException(status_code=415, detail=f"Unsupported file type: {file.content_type}")


@router.post("/register-multipart")
@limiter.limit("5/minute")
async def register_tourist_multipart(
    request: Request,
    full_name: str = Form(...),
    document_type: str = Form(...),
    document_number: str = Form(...),
    trip_start_date: str = Form(...),
    trip_end_date: str = Form(...),
    destination_state: str = Form(...),
    emergency_contact_name: Optional[str] = Form(None),
    emergency_contact_phone: Optional[str] = Form(None),
    blood_group: Optional[str] = Form("Unknown"),
    date_of_birth: Optional[str] = Form("1970-01-01"),
    nationality: Optional[str] = Form("IN"),
    selected_destinations_json: str = Form("[]"),
    profile_photo: UploadFile = File(...),
    document_scan: UploadFile = File(...),
    db: AsyncSession = Depends(get_db),
):
    """
    Advanced Registration (V3.1): Supports multipart/form-data for files.
    """
    try:
        with open("call_marker.txt", "a") as f:
            f.write(f"Function called at {datetime.datetime.now()}\n")
        # 1. File Validation
        await validate_file(profile_photo, MAX_PHOTO_SIZE, ["image/jpeg", "image/png"])
        await validate_file(document_scan, MAX_DOC_SIZE, ["image/jpeg", "image/png", "application/pdf"])

        # 2. Parse nested JSON
        try:
            dest_list = json.loads(selected_destinations_json)
            selected_destinations = [DestinationVisit(**d) for d in dest_list]
        except Exception as e:
            raise HTTPException(status_code=422, detail=f"Invalid selected_destinations format: {e}")

        # 3. ID Generation
        state_codes = {"Uttarakhand": "UK", "Meghalaya": "ML", "Arunachal Pradesh": "AR", "Assam": "AS"}
        state_code = state_codes.get(destination_state, "XX")
        year = datetime.datetime.now().year
        tourist_id = f"TID-{year}-{state_code}-{uuid.uuid4().hex[:5].upper()}"

        # 4. Identity v3
        tuid = generate_tuid(document_type, document_number, date_of_birth, nationality)
        doc_hash = hash_document_number(document_number)

        existing = await crud.get_tourist_by_doc_hash(db, doc_hash)
        if existing:
            raise HTTPException(status_code=409, detail={"error": "Document already registered", "tourist_id": existing.get("tourist_id")})

        # 5. Secure File Storage
        upload_dir = os.path.join("uploaded_files", f"tourist_{tourist_id}")
        os.makedirs(upload_dir, exist_ok=True)

        photo_ext = profile_photo.filename.split(".")[-1] if "." in profile_photo.filename else "jpg"
        doc_ext = document_scan.filename.split(".")[-1] if "." in document_scan.filename else "pdf"

        photo_path = os.path.join(upload_dir, f"{uuid.uuid4()}_profile.{photo_ext}")
        doc_path = os.path.join(upload_dir, f"{uuid.uuid4()}_doc.{doc_ext}")

        import aiofiles
        async with aiofiles.open(photo_path, "wb") as f:
            await f.write(await profile_photo.read())
        async with aiofiles.open(doc_path, "wb") as f:
            await f.write(await document_scan.read())

        # 6. Finalize Config
        config = derive_tourist_config(selected_destinations, destination_state)
        qr_jwt = None
        try:
            qr_service = _get_qr_service()
            qr_jwt = qr_service.sign_qr_jwt(tuid, full_name, nationality)
        except:
            pass

        # 7. Persist
        from app.models.schemas import TouristRegister as TR
        try:
            tourist_model = TR(
                full_name=full_name,
                document_type=document_type,
                document_number=document_number,
                emergency_contact_name=emergency_contact_name,
                emergency_contact_phone=emergency_contact_phone,
                trip_start_date=datetime.datetime.fromisoformat(trip_start_date),
                trip_end_date=datetime.datetime.fromisoformat(trip_end_date),
                destination_state=destination_state,
                selected_destinations=selected_destinations,
                blood_group=blood_group,
                date_of_birth=date_of_birth,
                nationality=nationality,
                photo_object_key=photo_path,
                document_object_key=doc_path,
            )
        except Exception as e:
            # Structured 422 logging (FIX #3)
            error_detail = str(e)
            if hasattr(e, "errors") and callable(e.errors):
                error_detail = jsonable_encoder(e.errors())

            logger.error(f"Registration validation failed [TUID: {tuid}]: {error_detail}")
            raise HTTPException(status_code=422, detail=error_detail)

        tourist_data = await crud.create_tourist(
            db,
            tourist_model,
            tourist_id,
            config,
            tuid=tuid,
            document_number_hash=doc_hash,
            qr_jwt=qr_jwt,
        )
        # Commit so the row is visible to subsequent reads
        await db.commit()

        # FIX BUG 3: Reload via _tourist_to_dict so photo_object_key, tuid,
        # and all fields are guaranteed in the response (legacy_data from
        # model_dump() may be missing photo_object_key on some code paths).
        reloaded = await crud.get_tourist(db, tourist_id)
        if reloaded:
            tourist_data = reloaded

        access_token = create_jwt_token(tourist_id)
        refresh_token = create_jwt_token(tourist_id, is_refresh=True)

        return {
            "tourist": tourist_data,
            "token": access_token,
            "refresh_token": refresh_token,
            "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Fatal error in register_tourist_multipart: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal Server Error")


def _get_remaining_lockout_seconds(tourist_id: str) -> int:
    """Get remaining lockout seconds for a tourist."""
    if tourist_id not in _login_attempts:
        return 0
    attempts = _login_attempts[tourist_id]
    if len(attempts) < MAX_LOGIN_ATTEMPTS:
        return 0
    last_attempt = attempts[-1]
    elapsed = (datetime.datetime.now() - last_attempt).total_seconds()
    remaining = max(0, LOCKOUT_SECONDS - int(elapsed))
    return remaining

@router.post(
    "/login",
    responses={
        429: {
            "description": "Rate limit exceeded or brute-force lockout",
            "content": {
                "application/json": {
                    "example": {
                        "detail": "Too many failed login attempts.",
                        "retry_after_seconds": 900,
                        "lockout_minutes": 15
                    }
                }
            }
        }
    }
)
@limiter.limit("10/minute")  # Rate limit per IP
async def login_tourist(
    request: Request,
    login_req: TouristLoginRequest,
    db: AsyncSession = Depends(get_db)
):
    """Login / retrieve tourist data by ID with brute-force protection.

    Lockout: 5 failed attempts → 15-minute lockout
    """
    tourist_id = (login_req.tourist_id or "").strip()
    if not tourist_id:
        raise HTTPException(status_code=400, detail="tourist_id is required")
    if not re.match(r"^TID-\d{4}-[A-Z]{2}-[A-Z0-9]{5}$", tourist_id):
        raise HTTPException(status_code=400, detail="Invalid tourist_id format")

    # Check brute-force protection
    remaining_lockout = _get_remaining_lockout_seconds(tourist_id)
    if remaining_lockout > 0:
        raise HTTPException(
            status_code=429,
            detail={
                "error": "Account temporarily locked due to failed login attempts",
                "retry_after_seconds": remaining_lockout,
                "lockout_minutes": remaining_lockout // 60,
                "message": f"Too many failed attempts. Try again in {remaining_lockout // 60} minutes."
            }
        )

    tourist_data = await crud.get_tourist(db, tourist_id)
    if not tourist_data:
        _record_failed_login(tourist_id)
        raise HTTPException(
            status_code=404,
            detail={
                "error": "Tourist not found",
                "remaining_attempts": max(0, MAX_LOGIN_ATTEMPTS - len(_login_attempts.get(tourist_id, [])))
            }
        )

    # Success - clear failed attempts
    if tourist_id in _login_attempts:
        del _login_attempts[tourist_id]

    access_token = create_jwt_token(tourist_id)
    refresh_token = create_jwt_token(tourist_id, is_refresh=True)

    return {
        "tourist": tourist_data,
        "token": access_token,
        "refresh_token": refresh_token,
        "expires_in": settings.JWT_ACCESS_EXPIRY_MINUTES * 60,
    }


@router.post("/refresh-qr")
async def refresh_qr_code(
    tourist_id: str = Depends(get_current_tourist),
    db: AsyncSession = Depends(get_db),
):
    """
    Refresh the QR JWT for the authenticated tourist.
    Call this when the existing QR is within 30 days of expiry.
    Returns the new QR JWT and its expiry timestamp.
    """
    tourist_data = await crud.get_tourist(db, tourist_id)
    if not tourist_data:
        raise HTTPException(status_code=404, detail="Tourist not found")

    tuid = tourist_data.get("tuid") or tourist_id
    full_name = tourist_data.get("full_name", "")
    nationality = tourist_data.get("nationality", "IN")

    try:
        qr_service = _get_qr_service()
        new_qr_jwt = qr_service.sign_qr_jwt(tuid, full_name, nationality)
    except Exception as e:
        raise HTTPException(status_code=503, detail=f"QR signing unavailable: {e}")

    await crud.update_tourist_qr(db, tourist_id, new_qr_jwt)

    expiry = datetime.datetime.utcnow() + datetime.timedelta(days=settings.QR_JWT_EXPIRY_DAYS)
    return {
        "qr_data": new_qr_jwt,
        "expires_at": expiry.isoformat() + "Z",
        "tuid": tuid,
    }
