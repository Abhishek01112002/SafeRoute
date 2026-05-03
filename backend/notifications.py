# backend/notifications.py
# SOS notification dispatch — Firebase push (primary) + Twilio SMS fallback.

import os, logging
from typing import Optional

logger = logging.getLogger("saferoute.notifications")

# ── Firebase Push ─────────────────────────────────────────────────────────────

_firebase_app = None

def _get_firebase():
    global _firebase_app
    if _firebase_app:
        return _firebase_app
    creds_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
    if not creds_path or not os.path.exists(creds_path):
        logger.warning("Firebase credentials not configured — push notifications disabled")
        return None
    try:
        import firebase_admin
        from firebase_admin import credentials
        cred = credentials.Certificate(creds_path)
        _firebase_app = firebase_admin.initialize_app(cred)
        return _firebase_app
    except Exception as e:
        logger.error(f"Firebase init failed: {e}")
        return None

def send_push(fcm_token: str, title: str, body: str, data: Optional[dict] = None) -> bool:
    app = _get_firebase()
    if not app:
        return False
    try:
        from firebase_admin import messaging
        msg = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={k: str(v) for k, v in (data or {}).items()},
            token=fcm_token,
            android=messaging.AndroidConfig(priority="high"),
        )
        messaging.send(msg)
        logger.info(f"Push sent to {fcm_token[:10]}...")
        return True
    except Exception as e:
        logger.error(f"Push failed: {e}")
        return False

# ── SMS Fallback (Twilio) ─────────────────────────────────────────────────────

def send_sms(phone: str, message: str) -> bool:
    """Consolidated SMS dispatcher using Twilio."""
    account_sid = os.getenv("TWILIO_ACCOUNT_SID")
    auth_token = os.getenv("TWILIO_AUTH_TOKEN")
    from_number = os.getenv("TWILIO_FROM_NUMBER")

    if not all([account_sid, auth_token, from_number]):
        logger.warning("Twilio credentials missing — SMS fallback disabled")
        return False

    try:
        from twilio.rest import Client
        client = Client(account_sid, auth_token)
        client.messages.create(
            body=message,
            from_=from_number,
            to=phone,
        )
        logger.info(f"SMS sent to {phone}")
        return True
    except Exception as e:
        logger.error(f"Twilio exception: {e}")
        return False

# ── SOS Dispatch ──────────────────────────────────────────────────────────────

def dispatch_sos(
    tourist_id: str,
    tourist_name: str,
    lat: float,
    lng: float,
    trigger_type: str,
    authority_fcm_tokens: list[str],
    authority_phones: list[str],
):
    """Fire-and-forget SOS dispatch. Tries push first, Twilio SMS as fallback."""
    title = f"🆘 SOS ALERT — {trigger_type}"
    body  = f"{tourist_name} needs help at ({lat:.5f}, {lng:.5f})"
    data  = {
        "tourist_id":   tourist_id,
        "latitude":     lat,
        "longitude":    lng,
        "trigger_type": trigger_type,
        "type":         "SOS_ALERT",
    }
    sms_text = f"[SafeRoute SOS] {body} — Tourist ID: {tourist_id}"

    # Try push notifications first
    push_sent = any(send_push(token, title, body, data) for token in authority_fcm_tokens)

    # Always send SMS fallback to authority phones if push fails or as additional redundancy
    # Here we follow the logic: if push fails OR always for redundancy
    if not push_sent or os.getenv("ALWAYS_SEND_SMS", "false").lower() == "true":
        for phone in authority_phones:
            send_sms(phone, sms_text)

    logger.info(
        f"SOS dispatched: tourist={tourist_id} push={'OK' if push_sent else 'FAIL'} "
        f"sms_targets={len(authority_phones)}"
    )
