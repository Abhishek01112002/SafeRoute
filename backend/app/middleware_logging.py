# app/middleware_logging.py
#
# SafeRoute Request/Response Logging Middleware
# ──────────────────────────────────────────────
# Logs every HTTP request with:
#   - method, path, status code, duration (ms)
#   - correlation ID (from X-Correlation-ID header or auto-generated)
#   - tourist_id / authority_id (from JWT, if present)
#   - user agent, ip address
#
# This is a pure OBSERVABILITY layer. Zero business logic.
# Add to app in main.py with: app.add_middleware(RequestLoggingMiddleware)

import time
import uuid
import re
import logging
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response
from app.logging_config import get_logger, set_correlation_id

log = get_logger("http")

# Paths to skip detailed logging (health checks would spam logs)
_SKIP_LOGGING_PATHS = {"/health", "/favicon.ico", "/.well-known"}

# Regex to extract sub from JWT without full verification (just for logging)
_JWT_SUB_PATTERN = re.compile(r'"sub"\s*:\s*"([^"]+)"')


def _extract_subject_from_bearer(auth_header: str | None) -> str | None:
    """Best-effort extraction of 'sub' from JWT payload for log context."""
    if not auth_header or not auth_header.startswith("Bearer "):
        return None
    try:
        import base64
        token = auth_header[7:]
        parts = token.split(".")
        if len(parts) != 3:
            return None
        payload_b64 = parts[1]
        # Fix padding
        padding = 4 - len(payload_b64) % 4
        payload_b64 += "=" * padding
        payload_json = base64.urlsafe_b64decode(payload_b64).decode("utf-8", errors="ignore")
        match = _JWT_SUB_PATTERN.search(payload_json)
        return match.group(1) if match else None
    except Exception:
        return None


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """
    Logs every request as two structured JSON lines:
      1. request.received   — on arrival
      2. request.completed  — after response, with status + duration_ms

    Example output (pretty-printed for readability):
    {
      "ts": "2025-05-04T06:12:33.421Z",
      "level": "INFO",
      "cid": "3f2a1b...",
      "event": "request.received",
      "method": "POST",
      "path": "/sos/trigger",
      "subject": "TID-2025-UK-00123",
      "ip": "203.0.113.42",
      "ua": "Dart/3.0 (dart:io)"
    }
    {
      "ts": "2025-05-04T06:12:33.589Z",
      "level": "INFO",
      "cid": "3f2a1b...",
      "event": "request.completed",
      "method": "POST",
      "path": "/sos/trigger",
      "status": 200,
      "duration_ms": 168,
      "subject": "TID-2025-UK-00123"
    }
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        path = request.url.path

        # Skip noisy health-check logs
        if path in _SKIP_LOGGING_PATHS:
            return await call_next(request)

        # Resolve correlation ID (from mobile header or generate one)
        cid = request.headers.get("X-Correlation-ID") or str(uuid.uuid4())
        set_correlation_id(cid)
        request.state.correlation_id = cid

        method = request.method
        subject = _extract_subject_from_bearer(request.headers.get("Authorization"))
        ip = request.headers.get("X-Forwarded-For", request.client.host if request.client else "unknown")
        ua = request.headers.get("User-Agent", "")

        # Log: request arrived
        log.info(
            "request.received",
            method=method,
            path=path,
            subject=subject,
            ip=ip,
            ua=ua[:120],  # Truncate long UAs
        )

        start = time.perf_counter()
        status_code = 500  # Default if exception occurs

        try:
            response: Response = await call_next(request)
            status_code = response.status_code
        except Exception as exc:
            log.error(
                "request.unhandled_exception",
                method=method,
                path=path,
                subject=subject,
                error=str(exc),
                duration_ms=round((time.perf_counter() - start) * 1000),
            )
            raise
        finally:
            duration_ms = round((time.perf_counter() - start) * 1000)

            # Choose log level based on status
            if status_code >= 500:
                emit = log.error
            elif status_code >= 400:
                emit = log.warning
            else:
                emit = log.info

            emit(
                "request.completed",
                method=method,
                path=path,
                status=status_code,
                duration_ms=duration_ms,
                subject=subject,
            )

        # Echo correlation ID back to client
        response.headers["X-Correlation-ID"] = cid
        return response
