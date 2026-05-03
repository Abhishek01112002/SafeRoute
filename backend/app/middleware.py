# app/middleware.py
import uuid
import contextvars
from fastapi import Request
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded
from app.logging_config import logger

# Context variable to store correlation ID across async boundaries
_correlation_id_ctx = contextvars.ContextVar('correlation_id', default='-')

def get_correlation_id() -> str:
    """Get the current correlation ID from context."""
    return _correlation_id_ctx.get()

class CorrelationIdMiddleware:
    """ASGI middleware to inject and propagate correlation IDs."""

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await send(scope, receive, send)
            return

        request = Request(scope, receive)
        correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))

        # Set in context for logger access
        token = _correlation_id_ctx.set(correlation_id)
        request.state.correlation_id = correlation_id

        # Bind to logger context
        old_factory = logging.getLogRecordFactory()

        def record_factory(*args, **kwargs):
            record = old_factory(*args, **kwargs)
            record.correlation_id = correlation_id
            return record

        logging.setLogRecordFactory(record_factory)

        async def wrapped_send(message):
            if message["type"] == "http.response.start":
                headers = list(message.get("headers", []))
                headers.append((b"X-Correlation-ID", correlation_id.encode()))
                message["headers"] = headers
            await send(message)

        try:
            await send(scope, receive, wrapped_send)
        finally:
            _correlation_id_ctx.reset(token)
            logging.setLogRecordFactory(old_factory)

async def add_correlation_id(request: Request, call_next):
    """Middleware to inject a unique Correlation ID into every request/response."""
    correlation_id = request.headers.get("X-Correlation-ID", str(uuid.uuid4()))
    request.state.correlation_id = correlation_id

    # Bind to logging context for this request
    old_factory = logging.getLogRecordFactory()

    def record_factory(*args, **kwargs):
        record = old_factory(*args, **kwargs)
        record.correlation_id = correlation_id
        return record

    logging.setLogRecordFactory(record_factory)

    try:
        response = await call_next(request)
        response.headers["X-Correlation-ID"] = correlation_id
        return response
    finally:
        logging.setLogRecordFactory(old_factory)

async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded):
    """Custom handler for rate limit exceeded errors."""
    cid = getattr(request.state, 'correlation_id', '-')
    logger.warning(f"Rate limit exceeded: {request.url.path}", extra={'correlation_id': cid})
    return JSONResponse(
        status_code=429,
        content={
            "error": "Too many requests",
            "message": "Production rate limit exceeded. Please wait before retrying.",
            "retry_after": exc.detail,
            "correlation_id": cid,
        }
    )
