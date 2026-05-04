# app/logging_config.py
#
# SafeRoute Structured Logging
# ─────────────────────────────
# Outputs every log entry as a single-line JSON object for easy ingestion
# by log aggregators (Datadog, Loki, CloudWatch, etc.).
#
# Each line includes:
#   timestamp, level, correlation_id, event, module, extra fields...
#
# Usage:
#   from app.logging_config import get_logger
#   log = get_logger(__name__)
#   log.info("sos.triggered", tourist_id=tourist_id, lat=30.7, lng=79.0)
#   log.warning("auth.failed_login", email=email, attempts=5)
#   log.error("db.connection_failed", error=str(e))

import logging
import json
import datetime
import sys
import traceback
from typing import Any, Optional

# ────────────────────────────────────────────────────────────────
# Correlation ID context (populated by middleware per-request)
# ────────────────────────────────────────────────────────────────
import contextvars
_correlation_id_ctx: contextvars.ContextVar[str] = contextvars.ContextVar(
    "correlation_id", default="-"
)

def set_correlation_id(cid: str) -> None:
    _correlation_id_ctx.set(cid)

def get_correlation_id() -> str:
    return _correlation_id_ctx.get()


# ────────────────────────────────────────────────────────────────
# JSON Formatter — single-line structured output
# ────────────────────────────────────────────────────────────────
class StructuredJSONFormatter(logging.Formatter):
    """
    Outputs log records as single-line JSON.
    All extra keyword args passed to logger.info/warning/error
    are included in the output.
    """

    def format(self, record: logging.LogRecord) -> str:
        entry: dict[str, Any] = {
            "ts": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z",
            "level": record.levelname,
            "cid": getattr(record, "correlation_id", get_correlation_id()),
            "event": record.getMessage(),
            "module": record.module,
        }

        # Include any extra fields attached to the record
        standard_fields = {
            "args", "created", "exc_info", "exc_text", "filename",
            "funcName", "levelname", "levelno", "lineno", "message",
            "module", "msecs", "msg", "name", "pathname", "process",
            "processName", "relativeCreated", "stack_info", "thread",
            "threadName", "correlation_id",
        }
        for key, value in record.__dict__.items():
            if key not in standard_fields and not key.startswith("_"):
                try:
                    json.dumps(value)  # Only include JSON-serializable extras
                    entry[key] = value
                except (TypeError, ValueError):
                    entry[key] = str(value)

        # Format exception if present
        if record.exc_info and record.exc_info[1]:
            entry["exception"] = {
                "type": type(record.exc_info[1]).__name__,
                "message": str(record.exc_info[1]),
                "traceback": traceback.format_exception(*record.exc_info),
            }

        return json.dumps(entry, default=str)


# ────────────────────────────────────────────────────────────────
# Logger factory
# ────────────────────────────────────────────────────────────────
def setup_logging(level: str = "INFO") -> logging.Logger:
    """Configure the root saferoute logger. Call once on startup."""
    root = logging.getLogger("saferoute")
    root.setLevel(getattr(logging, level.upper(), logging.INFO))

    if not root.handlers:
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(StructuredJSONFormatter())
        root.addHandler(handler)

    return root


def get_logger(name: str) -> "BoundLogger":
    """
    Return a bound logger for a module/route.
    Usage:
        log = get_logger(__name__)
        log.info("tourist.registered", tourist_id=tid, tuid=tuid)
    """
    return BoundLogger(logging.getLogger(f"saferoute.{name}"))


# Convenience module-level logger (backward-compatible)
logger = setup_logging()


# ────────────────────────────────────────────────────────────────
# BoundLogger — structured keyword-arg logging
# ────────────────────────────────────────────────────────────────
class BoundLogger:
    """
    Thin wrapper that injects correlation_id and extra kwargs
    into every log call automatically.

    Usage:
        log.info("event.name", key=value, key2=value2)
    """

    def __init__(self, inner: logging.Logger) -> None:
        self._inner = inner

    def _emit(self, level: int, event: str, **kwargs: Any) -> None:
        extra = {"correlation_id": get_correlation_id(), **kwargs}
        self._inner.log(level, event, extra=extra)

    def debug(self, event: str, **kwargs: Any) -> None:
        self._emit(logging.DEBUG, event, **kwargs)

    def info(self, event: str, **kwargs: Any) -> None:
        self._emit(logging.INFO, event, **kwargs)

    def warning(self, event: str, **kwargs: Any) -> None:
        self._emit(logging.WARNING, event, **kwargs)

    def error(self, event: str, **kwargs: Any) -> None:
        self._emit(logging.ERROR, event, **kwargs)

    def critical(self, event: str, **kwargs: Any) -> None:
        self._emit(logging.CRITICAL, event, **kwargs)

    def exception(self, event: str, exc: Optional[BaseException] = None, **kwargs: Any) -> None:
        """Log at ERROR with full traceback."""
        self._inner.exception(event, exc_info=exc or True, extra={
            "correlation_id": get_correlation_id(), **kwargs
        })
