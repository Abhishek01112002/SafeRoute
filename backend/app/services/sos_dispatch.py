# app/services/sos_dispatch.py
import json
import urllib.request
import urllib.error
from app.config import settings
from app.logging_config import logger

def dispatch_sos_alert(event: dict) -> dict:
    """
    Dispatch SOS to an external responder pipeline.
    Production deployments use SOS_DISPATCH_WEBHOOK_URL.
    """
    webhook_url = settings.SOS_DISPATCH_WEBHOOK_URL
    if not webhook_url:
        return {
            "status": "not_configured",
            "message": "SOS recorded locally; dispatch provider is not configured.",
        }

    request = urllib.request.Request(
        webhook_url,
        data=json.dumps(event).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=5) as response:
            status = "delivered" if 200 <= response.status < 300 else "failed"
            return {
                "status": status,
                "provider_status": response.status,
            }
    except (urllib.error.URLError, TimeoutError) as exc:
        logger.error(f"SOS dispatch failed: {exc}")
        return {
            "status": "failed",
            "message": str(exc),
        }
