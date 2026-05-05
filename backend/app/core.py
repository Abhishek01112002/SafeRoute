# app/core.py
import os
# CRITICAL: Clear REDIS_URL before dotenv in config.py loads it
# This forces in-memory rate limiting instead of Redis
if "REDIS_URL" in os.environ:
    del os.environ["REDIS_URL"]

import base64
import hashlib

import bcrypt
from slowapi import Limiter
from slowapi.util import get_remote_address


class PasswordContext:
    """Small password hashing adapter with passlib-like hash/verify methods."""

    _PREFIX = "bcrypt_sha256$"

    @staticmethod
    def _digest(password: str) -> bytes:
        digest = hashlib.sha256(password.encode("utf-8")).digest()
        return base64.b64encode(digest)

    def hash(self, password: str) -> str:
        hashed = bcrypt.hashpw(self._digest(password), bcrypt.gensalt(rounds=12))
        return self._PREFIX + hashed.decode("ascii")

    def verify(self, password: str, stored_hash: str) -> bool:
        if not stored_hash:
            return False

        if stored_hash.startswith(self._PREFIX):
            bcrypt_hash = stored_hash[len(self._PREFIX):].encode("ascii")
            return bcrypt.checkpw(self._digest(password), bcrypt_hash)

        # Backward compatibility for authority records created with passlib bcrypt.
        try:
            return bcrypt.checkpw(password.encode("utf-8"), stored_hash.encode("ascii"))
        except ValueError:
            return False


pwd_context = PasswordContext()

# Global Rate Limiter - uses memory:// since REDIS_URL is cleared above
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri="memory://"
)
