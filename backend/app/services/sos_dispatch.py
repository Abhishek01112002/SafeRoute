# app/services/sos_dispatch.py
import json
import time
import urllib.parse
import urllib.request
import urllib.error
from app.config import settings
from app.logging_config import get_logger

logger = get_logger("sos_dispatch")

def dispatch_sos_alert(event: dict) -> dict:
    """
    Dispatch SOS to an external responder pipeline.
    Production deployments use SOS_DISPATCH_WEBHOOK_URL.
    """
    webhook_url = settings.SOS_DISPATCH_WEBHOOK_URL
    if not webhook_url:
        logger.warning(
            "sos.dispatch.not_configured",
            tourist_id=event.get("tourist_id"),
        )
        return {
            "status": "not_configured",
            "message": "SOS recorded locally; dispatch provider is not configured.",
        }

    correlation_id = event.get("correlation_id") or "-"
    payload = json.dumps(event).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "X-Correlation-ID": correlation_id,
    }

    last_error = ""
    for attempt in range(1, 4):
        request = urllib.request.Request(
            webhook_url,
            data=payload,
            headers=headers,
            method="POST",
        )
        try:
            logger.info(
                "sos.dispatch.attempt",
                attempt=attempt,
                webhook_host=urllib.parse.urlparse(webhook_url).netloc,
                tourist_id=event.get("tourist_id"),
            )
            with urllib.request.urlopen(request, timeout=5) as response:
                status = "delivered" if 200 <= response.status < 300 else "failed"
                logger.info(
                    "sos.dispatch.completed",
                    attempt=attempt,
                    status=status,
                    provider_status=response.status,
                    tourist_id=event.get("tourist_id"),
                )
                return {
                    "status": status,
                    "provider_status": response.status,
                    "attempts": attempt,
                }
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = str(exc)
            logger.error(
                "sos.dispatch.failed_attempt",
                attempt=attempt,
                error=last_error,
                tourist_id=event.get("tourist_id"),
            )
            if attempt < 3:
                time.sleep(0.25 * attempt)

    return {
        "status": "failed",
        "message": last_error,
        "attempts": 3,
    }
