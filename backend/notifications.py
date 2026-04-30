# backend/notifications.py
# SOS notification dispatch — Firebase push (primary) + SMS fallback.

import os, json, logging
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

# ── SMS Fallback ──────────────────────────────────────────────────────────────

def send_sms(phone: str, message: str) -> bool:
    provider = os.getenv("SMS_PROVIDER", "").lower()
    if provider == "fast2sms":
        return _fast2sms(phone, message)
    elif provider == "twilio":
        return _twilio(phone, message)
    logger.warning("No SMS provider configured")
    return False

def _fast2sms(phone: str, message: str) -> bool:
    import requests
    key = os.getenv("FAST2SMS_API_KEY")
    if not key:
        return False
    try:
        r = requests.post(
            "https://www.fast2sms.com/dev/bulkV2",
            headers={"authorization": key},
            json={"route": "q", "message": message, "numbers": phone},
            timeout=8,
        )
        result = r.json()
        success = result.get("return", False)
        if not success:
            logger.error(f"Fast2SMS error: {result}")
        return success
    except Exception as e:
        logger.error(f"Fast2SMS exception: {e}")
        return False

def _twilio(phone: str, message: str) -> bool:
    try:
        from twilio.rest import Client
        client = Client(os.getenv("TWILIO_ACCOUNT_SID"), os.getenv("TWILIO_AUTH_TOKEN"))
        client.messages.create(
            body=message,
            from_=os.getenv("TWILIO_FROM_NUMBER"),
            to=phone,
        )
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
    """Fire-and-forget SOS dispatch. Tries push first, SMS as fallback."""
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

    push_sent = any(send_push(token, title, body, data) for token in authority_fcm_tokens)
    if not push_sent:
        # SMS fallback when push fails or no FCM token
        for phone in authority_phones:
            send_sms(phone, sms_text)

    logger.info(
        f"SOS dispatched: tourist={tourist_id} push={'OK' if push_sent else 'FAIL'} "
        f"sms_targets={len(authority_phones)}"
    )
