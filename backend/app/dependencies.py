# app/dependencies.py
from fastapi import Security, HTTPException, Depends
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from app.services.jwt_service import verify_jwt_payload, AuthPrincipal

security = HTTPBearer()

async def get_current_principal(
    credentials: HTTPAuthorizationCredentials = Security(security),
) -> AuthPrincipal:
    """Dependency to get the current authenticated principal."""
    token = credentials.credentials
    payload = verify_jwt_payload(token)
    if not payload:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    
    # Block refresh tokens from being used for access
    if payload.get("type") == "refresh":
        raise HTTPException(status_code=401, detail="Cannot use refresh token as access token")

    subject_id = payload.get("sub") or payload.get("tourist_id") or payload.get("authority_id")
    role = payload.get("role")
    if not subject_id or role not in {"tourist", "authority"}:
        raise HTTPException(status_code=401, detail="Invalid token claims")
    return AuthPrincipal(subject_id=subject_id, role=role)

async def get_current_tourist(principal: AuthPrincipal = Depends(get_current_principal)) -> str:
    """Dependency to get the current tourist id from JWT."""
    if principal.role != "tourist":
        raise HTTPException(status_code=403, detail="Tourist token required")
    return principal.subject_id

async def get_current_authority(principal: AuthPrincipal = Depends(get_current_principal)) -> str:
    """Dependency to get the current authority id from JWT."""
    if principal.role != "authority":
        raise HTTPException(status_code=403, detail="Authority token required")
    return principal.subject_id
