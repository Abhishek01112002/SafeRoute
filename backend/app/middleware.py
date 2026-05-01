# app/middleware.py
import uuid
from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from app.logging_config import logger

async def add_correlation_id(request: Request, call_next):
    """Middleware to inject a unique Correlation ID into every request/response."""
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    request.state.correlation_id = correlation_id
    response = await call_next(request)
    response.headers["X-Correlation-ID"] = correlation_id
    return response

async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    """Custom handler for rate limit exceeded errors."""
    logger.warning(f"Rate limit exceeded: {request.url.path}")
    return JSONResponse(
        status_code=429,
        content={
            "error": "Too many requests",
            "message": "Production rate limit exceeded. Please wait before retrying.",
            "retry_after": exc.detail
        }
    )
