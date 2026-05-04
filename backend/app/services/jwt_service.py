# app/services/jwt_service.py
import datetime
import jwt
import os
from typing import Optional, Dict, Any
from dataclasses import dataclass
from app.config import settings
from app.logging_config import logger

@dataclass(frozen=True)
class AuthPrincipal:
    subject_id: str
    role: str

# Load RSA keys from paths defined in settings
try:
    with open(settings.PRIVATE_KEY_PATH, "r") as f:
        PRIVATE_KEY = f.read()
    with open(settings.PUBLIC_KEY_PATH, "r") as f:
        PUBLIC_KEY = f.read()
    JWT_ALGORITHM = "RS256"
except FileNotFoundError:
    # Development fallback. Production validation requires RSA keys.
    PRIVATE_KEY = settings.JWT_SECRET
    PUBLIC_KEY = settings.JWT_SECRET
    JWT_ALGORITHM = "HS256"

def create_jwt_token(
    subject_id: str,
    role: str = "tourist",
    expires_delta: Optional[datetime.timedelta] = None,
    is_refresh: bool = False
) -> str:
    """Generate a role-scoped JWT token (Access or Refresh)."""
    if expires_delta:
        expire = datetime.datetime.utcnow() + expires_delta
    else:
        expire = datetime.datetime.utcnow() + datetime.timedelta(
            minutes=settings.JWT_ACCESS_EXPIRY_MINUTES if not is_refresh else 0,
            days=settings.JWT_REFRESH_EXPIRY_DAYS if is_refresh else 0
        )

    payload = {
        "sub": subject_id,
        "role": role,
        "exp": expire,
        "iat": datetime.datetime.utcnow(),
        "type": "refresh" if is_refresh else "access"
    }

    if role == "tourist":
        payload["tourist_id"] = subject_id
    elif role == "authority":
        payload["authority_id"] = subject_id

    return jwt.encode(payload, PRIVATE_KEY, algorithm=JWT_ALGORITHM)

def verify_jwt_payload(token: str) -> Optional[Dict[str, Any]]:
    """Verify JWT token and return the decoded payload."""
    try:
        # Allow only small clock skew; larger leeway lets expired access tokens pass.
        return jwt.decode(token, PUBLIC_KEY, algorithms=[JWT_ALGORITHM], leeway=5)
    except jwt.ExpiredSignatureError:
        logger.warning("JWT verification failed: Token expired")
        return None
    except jwt.InvalidTokenError as e:
        logger.warning(f"JWT verification failed: Invalid token ({e})")
        return None
    except Exception as e:
        logger.error(f"JWT verification failed: Unexpected error ({e})")
        return None

def verify_jwt_token(token: str) -> Optional[str]:
    """Verify JWT token and return the subject id."""
    payload = verify_jwt_payload(token)
    if not payload:
        return None
    return payload.get("sub") or payload.get("tourist_id") or payload.get("authority_id")
