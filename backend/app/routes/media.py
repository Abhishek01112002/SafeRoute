from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import FileResponse
import os

from app.models.schemas import MediaUploadRequest
from app.services.minio_service import minio_service
from app.dependencies import get_current_tourist
from app.core import limiter
import re

router = APIRouter()

ALLOWED_MIME_TYPES = {"image/jpeg", "image/png", "image/webp"}

@router.post("/upload-url")
@limiter.limit("5/minute")
async def get_upload_url(
    request: Request,
    payload: MediaUploadRequest
):
    """
    Get a presigned PUT URL to upload a photo directly to MinIO.
    This prevents large files from passing through the backend API.
    """
    if payload.content_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid content_type. Allowed: {ALLOWED_MIME_TYPES}"
        )

    # Validate TUID format: 24 alphanumeric characters
    if not payload.tuid or not re.match(r"^[a-zA-Z0-9]{24}$", payload.tuid):
        raise HTTPException(
            status_code=400,
            detail="Invalid TUID format (must be 24 alphanumeric characters).",
        )

    # 5MB limit
    if payload.file_size_bytes > 5 * 1024 * 1024:
        raise HTTPException(
            status_code=413,
            detail="File too large. Maximum size is 5MB."
        )
    if payload.file_size_bytes <= 0:
         raise HTTPException(
            status_code=400,
            detail="File size must be greater than 0."
         )

    if not minio_service.is_available:
         raise HTTPException(
            status_code=503,
            detail="Media storage is currently unavailable."
         )

    ext = payload.content_type.split("/")[-1]
    # Scoped to TUID for uniqueness and security
    object_key = f"tourist_photos/{payload.tuid}.{ext}"

    upload_url = minio_service.get_presigned_upload_url(
        object_key=object_key,
        content_type=payload.content_type,
        expiry_seconds=300 # 5 minutes
    )

    return {
        "upload_url": upload_url,
        "object_key": object_key,
        "expires_in": 300,
    }


@router.get("/download/{file_path:path}")
@limiter.limit("20/minute")
async def get_upload(
    request: Request,
    file_path: str,
    tourist_id: str = Depends(get_current_tourist),
):
    """
    Secure download: Returns the file only if the tourist is authenticated.
    Path format: uploaded_files/tourist_TID-XXXX/uuid_type.ext
    """
    # Security: Ensure they can only access their own files
    # A simple path check: "tourist_{tourist_id}" must be in the path
    if f"tourist_{tourist_id}" not in file_path or ".." in file_path:
        raise HTTPException(status_code=403, detail="Access denied to this file")

    # Only allow access to the uploaded_files directory
    if not file_path.startswith("uploaded_files/"):
        raise HTTPException(status_code=403, detail="Invalid file path")

    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="File not found")

    return FileResponse(file_path)
