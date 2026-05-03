# app/services/telemetry.py
"""
Telemetry and observability service.
Handles Sentry initialization and custom event tracking.
"""
import os
import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.sqlalchemy import SqlalchemyIntegration
from app.logging_config import logger

class TelemetryService:
    def __init__(self):
        self.enabled = False
        self._init_sentry()

    def _init_sentry(self):
        dsn = os.getenv("SENTRY_DSN")
        if not dsn:
            logger.info("📡 Telemetry: Sentry DSN not found. Performance tracking limited to logs.")
            return

        try:
            sentry_sdk.init(
                dsn=dsn,
                integrations=[
                    FastApiIntegration(),
                    SqlalchemyIntegration(),
                ],
                traces_sample_rate=1.0 if os.getenv("ENVIRONMENT") != "production" else 0.1,
                profiles_sample_rate=1.0 if os.getenv("ENVIRONMENT") != "production" else 0.1,
                environment=os.getenv("ENVIRONMENT", "development"),
            )
            self.enabled = True
            logger.info("✅ Telemetry: Sentry initialized.")
        except Exception as e:
            logger.error(f"🔴 Telemetry: Sentry initialization failed: {e}")

    def track_event(self, name: str, properties: dict = None):
        """Track a custom event. In dev, just logs. In prod, can send to Sentry/Mixpanel."""
        logger.info(f"📊 [Event] {name}: {properties or {}}")
        if self.enabled:
            with sentry_sdk.configure_scope() as scope:
                for k, v in (properties or {}).items():
                    scope.set_tag(f"event_{name}_{k}", v)
            sentry_sdk.capture_message(f"Event: {name}")

# Global singleton
telemetry = TelemetryService()
