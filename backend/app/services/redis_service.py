# app/services/redis_service.py
"""
Redis service with graceful degradation.
If Redis is unavailable, all operations are silent no-ops (cache miss / skip).
Rate limiter falls back to in-memory automatically via SlowAPI.
"""
import json
from typing import Optional, Any
from app.logging_config import logger
from app.config import settings

_redis_client = None


async def _get_client():
    """Lazy-initialize Redis async client. Returns None if unavailable."""
    global _redis_client
    if _redis_client is not None:
        return _redis_client
    if not settings.REDIS_URL:
        return None
    try:
        import redis.asyncio as aioredis
        _redis_client = aioredis.from_url(
            settings.REDIS_URL,
            decode_responses=True,
            socket_connect_timeout=2,
            socket_timeout=2,
        )
        await _redis_client.ping()
        logger.info("✅ Redis: Connection established.")
        return _redis_client
    except Exception as e:
        logger.error(f"🔴 Redis: Connection failed — falling back to no-cache mode. {e}")
        _redis_client = None
        return None


async def cache_get(key: str) -> Optional[str]:
    """Get a cached value. Returns None on miss or Redis failure (safe)."""
    try:
        client = await _get_client()
        if client is None:
            return None
        return await client.get(key)
    except Exception as e:
        logger.error(f"🔴 Redis cache_get failed (key={key}): {e}")
        return None


async def cache_set(key: str, value: Any, ttl: int = 60) -> None:
    """Set a cached value with TTL in seconds. Silent no-op on Redis failure."""
    try:
        client = await _get_client()
        if client is None:
            return
        serialized = value if isinstance(value, str) else json.dumps(value)
        await client.set(key, serialized, ex=ttl)
    except Exception as e:
        logger.error(f"🔴 Redis cache_set failed (key={key}): {e}")


async def cache_get_json(key: str) -> Optional[Any]:
    """Get and deserialize a JSON-cached value."""
    raw = await cache_get(key)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return None


async def cache_invalidate(key: str) -> None:
    """Delete a cached key. Silent no-op on Redis failure."""
    try:
        client = await _get_client()
        if client is None:
            return
        await client.delete(key)
    except Exception as e:
        logger.error(f"🔴 Redis cache_invalidate failed (key={key}): {e}")


async def ping() -> bool:
    """Health check — returns True if Redis is reachable."""
    try:
        client = await _get_client()
        if client is None:
            return False
        await client.ping()
        return True
    except Exception:
        return False
