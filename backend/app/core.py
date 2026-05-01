# app/core.py
from passlib.context import CryptContext
from slowapi import Limiter
from slowapi.util import get_remote_address

# Password hashing context
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Global Rate Limiter
limiter = Limiter(key_func=get_remote_address)
