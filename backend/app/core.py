# app/core.py
import os
# CRITICAL: Clear REDIS_URL before dotenv in config.py loads it
# This forces in-memory rate limiting instead of Redis
if "REDIS_URL" in os.environ:
    del os.environ["REDIS_URL"]

from passlib.context import CryptContext
from slowapi import Limiter
from slowapi.util import get_remote_address

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Global Rate Limiter - uses memory:// since REDIS_URL is cleared above
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri="memory://"
)
