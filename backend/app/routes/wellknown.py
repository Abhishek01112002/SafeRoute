# app/routes/wellknown.py
from fastapi import APIRouter, Response
from app.services.qr_service import qr_service

router = APIRouter()

@router.get("/qr-public-key")
async def get_qr_public_key():
    """
    Exposes the RS256 public key used to sign QR JWTs.
    Used by the authority mobile app to verify QRs while offline.
    """
    pem = qr_service.get_public_key_pem()
    if not pem:
        return Response(content="Public key unavailable", status_code=503)

    return Response(content=pem, media_type="text/plain")
