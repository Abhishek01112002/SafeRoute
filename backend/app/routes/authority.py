# app/routes/authority.py
from fastapi import APIRouter, HTTPException, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from app.db import crud
from app.dependencies import get_current_authority
from app.services.redis_service import cache_get_json, cache_set
from app.services.minio_service import minio_service
from app.services.identity_service import is_legacy_tourist_id, verify_tuid_format
from app.core import limiter
from typing import Optional

router = APIRouter()

@router.get("/scan/{scanned_id}")
@limiter.limit("30/minute")
async def scan_tourist(
    request: Request,
    scanned_id: str,
    authority_id: str = Depends(get_current_authority),
    db: AsyncSession = Depends(get_db)
):
    """
    Authority endpoint to scan a tourist's QR code (TUID or legacy TID).
    Includes Redis caching (60s) and generates a temporary photo URL.
    Writes to audit log.
    """
    # 1. Validate input format
    if not is_legacy_tourist_id(scanned_id) and not verify_tuid_format(scanned_id):
        raise HTTPException(status_code=400, detail="Invalid QR code format")

    # 2. Check Redis Cache
    cache_key = f"auth_scan:{authority_id}:{scanned_id}"
    cached_data = await cache_get_json(cache_key)
    if cached_data:
        # We still log cached reads for audit compliance
        await crud.create_scan_log(
            db=db,
            authority_id=authority_id,
            scanned_tuid=scanned_id,
            tourist_id=cached_data.get("tourist_id"),
            ip_address=request.client.host if request.client else None,
            user_agent=request.headers.get("user-agent"),
            photo_url_generated=cached_data.get("photo_url") is not None
        )
        return cached_data

    # 3. DB Lookup
    if is_legacy_tourist_id(scanned_id):
        tourist = await crud.get_tourist(db, scanned_id)
    else:
        tourist = await crud.get_tourist_by_tuid(db, scanned_id)

    if not tourist:
        raise HTTPException(status_code=404, detail="Tourist not found")

    # 4. Generate Presigned Photo URL (if applicable)
    photo_url = None
    if tourist.get("photo_object_key") and minio_service.is_available:
        photo_url = minio_service.get_presigned_download_url(
            tourist["photo_object_key"],
            expiry_seconds=300
        )

    # 5. Build Response (DO NOT include document_number_hash)
    response_data = {
        "tourist_id": tourist["tourist_id"],
        "tuid": tourist.get("tuid"),
        "full_name": tourist["full_name"],
        "date_of_birth": tourist.get("date_of_birth"),
        "nationality": tourist.get("nationality"),
        "blood_group": tourist.get("blood_group"),
        "risk_level": tourist.get("risk_level"),
        "migrated_from_legacy": tourist.get("migrated_from_legacy", False),
        "photo_url": photo_url,
        # Only return legacy base64 if no new photo exists
        "photo_base64_legacy": tourist.get("photo_base64") if not photo_url else None
    }

    # 6. Audit Log
    await crud.create_scan_log(
        db=db,
        authority_id=authority_id,
        scanned_tuid=scanned_id,
        tourist_id=tourist["tourist_id"],
        ip_address=request.client.host if request.client else None,
        user_agent=request.headers.get("user-agent"),
        photo_url_generated=photo_url is not None
    )

    # 7. Cache in Redis
    await cache_set(cache_key, response_data, ttl=60)

    return response_data
