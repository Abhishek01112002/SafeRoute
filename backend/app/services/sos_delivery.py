import asyncio
import json
import os
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from sqlalchemy import select, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db.session import AsyncSessionLocal
from app.logging_config import get_logger
from app.models.database import (
    Authority,
    AuthorityDevice,
    SOSEvent,
    SOSDeliveryAudit,
    SOSDispatchQueue,
    SOSProviderCircuit,
    Tourist,
)


log = get_logger("sos_delivery")

QUEUE_PENDING = "PENDING"
QUEUE_DISPATCHING = "DISPATCHING"
QUEUE_DELIVERED = "DELIVERED"
QUEUE_ESCALATED = "ESCALATED"
QUEUE_EXPIRED_NO_DELIVERY = "EXPIRED_NO_DELIVERY"
QUEUE_EXPIRED_NO_RESPONSE = "EXPIRED_NO_RESPONSE"
QUEUE_CANCELLED = "CANCELLED"

INCIDENT_ACTIVE = "ACTIVE"
INCIDENT_ACKNOWLEDGED = "ACKNOWLEDGED"
INCIDENT_ESCALATED = "ESCALATED"
INCIDENT_RESOLVED = "RESOLVED"
INCIDENT_EXPIRED_NO_DELIVERY = "EXPIRED_NO_DELIVERY"
INCIDENT_EXPIRED_NO_RESPONSE = "EXPIRED_NO_RESPONSE"

AUDIT_SUCCESS = "SUCCESS"
AUDIT_FAILED = "FAILED"
AUDIT_SKIPPED = "SKIPPED"
AUDIT_SKIPPED_CIRCUIT_OPEN = "SKIPPED_CIRCUIT_OPEN"


@dataclass
class ChannelResult:
    channel: str
    target: Optional[str]
    status: str
    provider_status: Optional[str] = None
    error_message: Optional[str] = None

    @property
    def success(self) -> bool:
        return self.status == AUDIT_SUCCESS

    @property
    def retryable_failure(self) -> bool:
        return self.status == AUDIT_FAILED


def _now() -> datetime:
    return datetime.now()


def public_status_message(event: SOSEvent, queue: Optional[SOSDispatchQueue]) -> str:
    state = queue.state if queue else event.delivery_state
    if event.incident_status == INCIDENT_ACKNOWLEDGED:
        return "Authority acknowledged your SOS."
    if event.incident_status == INCIDENT_RESOLVED:
        return "SOS response has been resolved."
    if state in {QUEUE_DELIVERED, QUEUE_ESCALATED}:
        return "Rescue network notified. Keep SOS visible and conserve battery."
    if state == QUEUE_EXPIRED_NO_DELIVERY:
        return "SOS is still stored, but no responder channel confirmed delivery. Try 112, move toward signal, or use BLE relay."
    if state == QUEUE_EXPIRED_NO_RESPONSE:
        return "Rescue network was notified, but no authority acknowledged yet. Keep trying local emergency options."
    return "SOS queued securely. SafeRoute is reaching authorities."


async def create_or_get_queued_sos(
    db: AsyncSession,
    *,
    tourist_id: str,
    tuid: Optional[str],
    latitude: float,
    longitude: float,
    trigger_type: str,
    timestamp: datetime,
    idempotency_key: str,
    source: str = "DIRECT",
    group_id: Optional[str] = None,
    relayed_by_tourist_id: Optional[str] = None,
    correlation_id: Optional[str] = None,
) -> tuple[SOSEvent, SOSDispatchQueue, bool]:
    existing = (
        await db.execute(
            select(SOSEvent).where(
                SOSEvent.tourist_id == tourist_id,
                SOSEvent.idempotency_key == idempotency_key,
            )
        )
    ).scalar_one_or_none()

    if existing:
        queue = (
            await db.execute(
                select(SOSDispatchQueue)
                .where(SOSDispatchQueue.sos_event_id == existing.id)
                .order_by(SOSDispatchQueue.created_at.desc())
                .limit(1)
            )
        ).scalar_one()
        return existing, queue, False

    event = SOSEvent(
        tourist_id=tourist_id,
        tuid=tuid,
        idempotency_key=idempotency_key,
        latitude=latitude,
        longitude=longitude,
        trigger_type=trigger_type,
        source=source,
        incident_status=INCIDENT_ACTIVE,
        delivery_state=QUEUE_PENDING,
        dispatch_status="queued",
        group_id=group_id,
        relayed_by_tourist_id=relayed_by_tourist_id,
        correlation_id=correlation_id,
        timestamp=timestamp,
        is_synced=False,
    )
    db.add(event)
    await db.flush()

    now = _now()
    queue = SOSDispatchQueue(
        queue_id=str(uuid.uuid4()),
        sos_event_id=event.id,
        tourist_id=tourist_id,
        tuid=tuid,
        idempotency_key=idempotency_key,
        latitude=latitude,
        longitude=longitude,
        trigger_type=trigger_type,
        state=QUEUE_PENDING,
        attempt_count=0,
        next_attempt_at=now,
        ttl_expires_at=now + timedelta(seconds=settings.SOS_DELIVERY_TTL_SECONDS),
    )
    db.add(queue)
    await db.flush()

    await write_audit(
        db,
        sos_event_id=event.id,
        queue_id=queue.queue_id,
        channel="QUEUE",
        target=None,
        status=AUDIT_SUCCESS,
        provider_status="QUEUED",
        attempt_number=0,
    )
    return event, queue, True


async def write_audit(
    db: AsyncSession,
    *,
    sos_event_id: int,
    queue_id: Optional[str],
    channel: str,
    target: Optional[str],
    status: str,
    provider_status: Optional[str] = None,
    error_message: Optional[str] = None,
    attempt_number: int = 0,
) -> None:
    db.add(
        SOSDeliveryAudit(
            audit_id=str(uuid.uuid4()),
            sos_event_id=sos_event_id,
            queue_id=queue_id,
            channel=channel,
            target=target,
            status=status,
            provider_status=provider_status,
            error_message=error_message,
            attempt_number=attempt_number,
        )
    )


async def get_status_payload(db: AsyncSession, event: SOSEvent) -> dict:
    queue = (
        await db.execute(
            select(SOSDispatchQueue)
            .where(SOSDispatchQueue.sos_event_id == event.id)
            .order_by(SOSDispatchQueue.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    return {
        "sos_id": event.id,
        "tourist_id": event.tourist_id,
        "incident_status": event.incident_status,
        "delivery_state": queue.state if queue else event.delivery_state,
        "dispatch_status": event.dispatch_status,
        "attempt_count": queue.attempt_count if queue else 0,
        "next_retry_at": queue.next_attempt_at.isoformat() if queue and queue.next_attempt_at else None,
        "acknowledged_at": event.acknowledged_at.isoformat() if event.acknowledged_at else None,
        "resolved_at": event.resolved_at.isoformat() if event.resolved_at else None,
        "message": public_status_message(event, queue),
    }


async def _is_circuit_open(db: AsyncSession, provider: str) -> bool:
    circuit = await db.get(SOSProviderCircuit, provider)
    if not circuit or circuit.state != "OPEN":
        return False
    if circuit.opened_until and circuit.opened_until <= _now():
        circuit.state = "HALF_OPEN"
        await db.flush()
        return False
    return True


async def _record_provider_success(db: AsyncSession, provider: str) -> None:
    circuit = await db.get(SOSProviderCircuit, provider)
    if not circuit:
        circuit = SOSProviderCircuit(provider=provider)
        db.add(circuit)
    circuit.state = "CLOSED"
    circuit.failure_count = 0
    circuit.opened_until = None
    circuit.last_success_at = _now()


async def _record_provider_failure(db: AsyncSession, provider: str) -> None:
    circuit = await db.get(SOSProviderCircuit, provider)
    if not circuit:
        circuit = SOSProviderCircuit(provider=provider, state="CLOSED", failure_count=0)
        db.add(circuit)
    circuit.failure_count = (circuit.failure_count or 0) + 1
    circuit.last_failure_at = _now()
    if circuit.failure_count >= settings.SOS_PROVIDER_FAILURE_THRESHOLD:
        circuit.state = "OPEN"
        circuit.opened_until = _now() + timedelta(seconds=settings.SOS_PROVIDER_CIRCUIT_COOLDOWN_SECONDS)


async def _authority_targets(db: AsyncSession, event: SOSEvent) -> tuple[list[str], list[str]]:
    phones = [
        p for p in (
            await db.execute(
                select(Authority.phone).where(Authority.status == "active", Authority.phone.is_not(None))
            )
        ).scalars().all()
        if p
    ]
    devices = [
        t for t in (
            await db.execute(select(AuthorityDevice.fcm_token))
        ).scalars().all()
        if t
    ]

    tourist = await db.get(Tourist, event.tourist_id)
    if tourist and tourist.emergency_contact_phone:
        phones.append(tourist.emergency_contact_phone)
    return sorted(set(phones)), sorted(set(devices))


async def _dispatch_webhook(event: SOSEvent) -> ChannelResult:
    url = settings.SOS_DISPATCH_WEBHOOK_URL
    if not url:
        return ChannelResult("WEBHOOK", None, AUDIT_SKIPPED, "NOT_CONFIGURED", "SOS_DISPATCH_WEBHOOK_URL is empty")

    payload = json.dumps(
        {
            "sos_id": event.id,
            "tourist_id": event.tourist_id,
            "tuid": event.tuid,
            "latitude": event.latitude,
            "longitude": event.longitude,
            "trigger_type": event.trigger_type,
            "timestamp": event.timestamp.isoformat() if event.timestamp else None,
        }
    ).encode("utf-8")

    def _send() -> ChannelResult:
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                if 200 <= response.status < 300:
                    return ChannelResult("WEBHOOK", url, AUDIT_SUCCESS, str(response.status))
                return ChannelResult("WEBHOOK", url, AUDIT_FAILED, str(response.status), "Non-2xx webhook response")
        except (urllib.error.URLError, TimeoutError) as exc:
            return ChannelResult("WEBHOOK", url, AUDIT_FAILED, "ERROR", str(exc))

    return await asyncio.to_thread(_send)


async def _dispatch_sms(event: SOSEvent, targets: list[str]) -> list[ChannelResult]:
    if not targets:
        return [ChannelResult("SMS", None, AUDIT_SKIPPED, "NO_TARGETS", "No authority or emergency-contact phone targets")]
    account_sid = os.getenv("TWILIO_ACCOUNT_SID")
    auth_token = os.getenv("TWILIO_AUTH_TOKEN")
    from_number = os.getenv("TWILIO_FROM_NUMBER")
    if not all([account_sid, auth_token, from_number]):
        return [ChannelResult("SMS", None, AUDIT_SKIPPED, "NOT_CONFIGURED", "Twilio credentials missing")]

    message = (
        f"[SafeRoute SOS] {event.trigger_type} from {event.tourist_id} "
        f"at {event.latitude:.5f},{event.longitude:.5f}"
    )

    def _send_one(phone: str) -> ChannelResult:
        try:
            from twilio.rest import Client

            client = Client(account_sid, auth_token)
            sent = client.messages.create(body=message, from_=from_number, to=phone)
            return ChannelResult("SMS", phone, AUDIT_SUCCESS, getattr(sent, "sid", "SENT"))
        except Exception as exc:
            return ChannelResult("SMS", phone, AUDIT_FAILED, "ERROR", str(exc))

    return await asyncio.gather(*[asyncio.to_thread(_send_one, phone) for phone in targets])


async def _dispatch_fcm(event: SOSEvent, tokens: list[str]) -> list[ChannelResult]:
    if not tokens:
        return [ChannelResult("FCM", None, AUDIT_SKIPPED, "NO_TARGETS", "No authority FCM tokens")]
    creds_path = os.getenv("FIREBASE_CREDENTIALS_PATH")
    if not creds_path or not os.path.exists(creds_path):
        return [ChannelResult("FCM", None, AUDIT_SKIPPED, "NOT_CONFIGURED", "Firebase credentials missing")]

    def _send_one(token: str) -> ChannelResult:
        try:
            import firebase_admin
            from firebase_admin import credentials, messaging

            if not firebase_admin._apps:
                firebase_admin.initialize_app(credentials.Certificate(creds_path))
            msg = messaging.Message(
                notification=messaging.Notification(
                    title=f"SafeRoute SOS - {event.trigger_type}",
                    body=f"{event.tourist_id} at {event.latitude:.5f},{event.longitude:.5f}",
                ),
                data={"sos_id": str(event.id), "tourist_id": event.tourist_id},
                token=token,
                android=messaging.AndroidConfig(priority="high"),
            )
            provider_id = messaging.send(msg)
            return ChannelResult("FCM", token[:12], AUDIT_SUCCESS, provider_id)
        except Exception as exc:
            return ChannelResult("FCM", token[:12], AUDIT_FAILED, "ERROR", str(exc))

    return await asyncio.gather(*[asyncio.to_thread(_send_one, token) for token in tokens])


async def dispatch_queue_once(db: AsyncSession, queue: SOSDispatchQueue, event: SOSEvent) -> None:
    queue.state = QUEUE_DISPATCHING
    queue.claimed_at = _now()
    queue.attempt_count = (queue.attempt_count or 0) + 1
    event.delivery_state = QUEUE_DISPATCHING
    event.dispatch_status = "dispatching"
    await db.flush()

    phones, fcm_tokens = await _authority_targets(db, event)
    attempt = queue.attempt_count
    channel_results: list[ChannelResult] = []

    providers = [
        ("WEBHOOK", lambda: _dispatch_webhook(event)),
        ("SMS", lambda: _dispatch_sms(event, phones)),
        ("FCM", lambda: _dispatch_fcm(event, fcm_tokens)),
    ]
    runnable = []
    for provider, call in providers:
        if await _is_circuit_open(db, provider):
            channel_results.append(ChannelResult(provider, None, AUDIT_SKIPPED_CIRCUIT_OPEN, "CIRCUIT_OPEN"))
        else:
            runnable.append((provider, call))

    grouped = await asyncio.gather(*[call() for _, call in runnable]) if runnable else []
    provider_results: dict[str, list[ChannelResult]] = {}
    for (provider, _), group in zip(runnable, grouped):
        if not isinstance(group, list):
            group = [group]
        provider_results[provider] = group
        channel_results.extend(group)

    for provider, results in provider_results.items():
        if any(r.success for r in results):
            await _record_provider_success(db, provider)
        elif any(r.retryable_failure for r in results):
            await _record_provider_failure(db, provider)

    for result in channel_results:
        await write_audit(
            db,
            sos_event_id=event.id,
            queue_id=queue.queue_id,
            channel=result.channel,
            target=result.target,
            status=result.status,
            provider_status=result.provider_status,
            error_message=result.error_message,
            attempt_number=attempt,
        )

    if any(r.success for r in channel_results):
        queue.state = QUEUE_DELIVERED
        queue.delivered_at = _now()
        queue.next_attempt_at = None
        queue.last_error = None
        event.delivery_state = QUEUE_DELIVERED
        event.dispatch_status = "delivered"
        event.delivery_summary = "At least one responder channel accepted the SOS."
        return

    if queue.ttl_expires_at <= _now():
        queue.state = QUEUE_EXPIRED_NO_DELIVERY
        queue.next_attempt_at = None
        event.delivery_state = QUEUE_EXPIRED_NO_DELIVERY
        event.dispatch_status = "expired_no_delivery"
        event.incident_status = INCIDENT_EXPIRED_NO_DELIVERY
        return

    queue.state = QUEUE_PENDING
    queue.next_attempt_at = _now() + timedelta(seconds=settings.SOS_RETRY_INTERVAL_SECONDS)
    queue.last_error = "; ".join(filter(None, [r.error_message for r in channel_results]))[:1000]
    event.delivery_state = QUEUE_PENDING
    event.dispatch_status = "retry_scheduled"


async def maintain_state_transitions(db: AsyncSession) -> None:
    now = _now()
    delivered = (
        await db.execute(
            select(SOSDispatchQueue, SOSEvent)
            .join(SOSEvent, SOSEvent.id == SOSDispatchQueue.sos_event_id)
            .where(
                SOSDispatchQueue.state == QUEUE_DELIVERED,
                SOSDispatchQueue.delivered_at.is_not(None),
                SOSDispatchQueue.delivered_at <= now - timedelta(seconds=settings.SOS_ESCALATE_AFTER_SECONDS),
                SOSEvent.acknowledged_at.is_(None),
                SOSEvent.resolved_at.is_(None),
            )
        )
    ).all()
    for queue, event in delivered:
        queue.state = QUEUE_ESCALATED
        queue.escalated_at = now
        event.incident_status = INCIDENT_ESCALATED
        event.delivery_state = QUEUE_ESCALATED
        event.dispatch_status = "escalated"
        await write_audit(
            db,
            sos_event_id=event.id,
            queue_id=queue.queue_id,
            channel="ADMIN",
            target="all-authorities",
            status=AUDIT_SUCCESS,
            provider_status="ESCALATED",
            attempt_number=queue.attempt_count,
        )

    expired_response = (
        await db.execute(
            select(SOSDispatchQueue, SOSEvent)
            .join(SOSEvent, SOSEvent.id == SOSDispatchQueue.sos_event_id)
            .where(
                SOSDispatchQueue.state == QUEUE_ESCALATED,
                SOSDispatchQueue.escalated_at.is_not(None),
                SOSDispatchQueue.escalated_at <= now - timedelta(seconds=settings.SOS_EXPIRE_RESPONSE_AFTER_SECONDS),
                SOSEvent.acknowledged_at.is_(None),
                SOSEvent.resolved_at.is_(None),
            )
        )
    ).all()
    for queue, event in expired_response:
        queue.state = QUEUE_EXPIRED_NO_RESPONSE
        event.incident_status = INCIDENT_EXPIRED_NO_RESPONSE
        event.delivery_state = QUEUE_EXPIRED_NO_RESPONSE
        event.dispatch_status = "expired_no_response"


async def process_due_queue_once(limit: int = 10) -> int:
    processed = 0
    async with AsyncSessionLocal() as db:
        async with db.begin():
            await maintain_state_transitions(db)
            now = _now()
            query = (
                select(SOSDispatchQueue)
                .where(
                    SOSDispatchQueue.state == QUEUE_PENDING,
                    or_(SOSDispatchQueue.next_attempt_at.is_(None), SOSDispatchQueue.next_attempt_at <= now),
                )
                .order_by(SOSDispatchQueue.created_at.asc())
                .limit(limit)
            )
            if db.get_bind().dialect.name != "sqlite":
                query = query.with_for_update(skip_locked=True)
            queues = (await db.execute(query)).scalars().all()
            for queue in queues:
                event = await db.get(SOSEvent, queue.sos_event_id)
                if not event:
                    queue.state = QUEUE_CANCELLED
                    continue
                await dispatch_queue_once(db, queue, event)
                processed += 1
    return processed


async def dispatch_worker_loop(stop_event: asyncio.Event) -> None:
    log.info("sos.worker.started")
    while not stop_event.is_set():
        try:
            await process_due_queue_once()
        except Exception as exc:
            log.error("sos.worker.tick_failed", error=str(exc))
        try:
            await asyncio.wait_for(stop_event.wait(), timeout=5)
        except asyncio.TimeoutError:
            pass
    log.info("sos.worker.stopped")


def idempotency_from_compact_hash(origin_tuid_suffix: str, idempotency_hash: str, unix_minute: int) -> str:
    return f"BLE-{origin_tuid_suffix.upper()}-{idempotency_hash.lower()}-{unix_minute}"
