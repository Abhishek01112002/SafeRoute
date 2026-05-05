# backend/tests/test_location_routes.py
#
# Tests for /location/ping endpoint.
# Covers: auth enforcement, coordinate and speed validation, happy path.

import pytest
import datetime
from tests.conftest import valid_location_payload, TEST_TOURIST_ID


class TestLocationPingAuth:
    """Auth enforcement."""

    def test_location_ping_requires_auth(self, client):
        """POST /location/ping without token → 401 or 403."""
        resp = client.post("/location/ping", json=valid_location_payload())
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 without auth, got {resp.status_code}: {resp.text}"
        )

    def test_location_ping_with_expired_token(self, client, expired_token_header):
        """POST /location/ping with expired JWT → 401."""
        resp = client.post(
            "/location/ping",
            json=valid_location_payload(),
            headers=expired_token_header,
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 with expired token, got {resp.status_code}: {resp.text}"
        )


class TestLocationPingValidation:
    """Input validation tests — matching Pydantic schema constraints."""

    def test_location_ping_latitude_too_high(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["latitude"] = 95.0  # > 90
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 for lat=95, got {resp.status_code}: {resp.text}"
        )

    def test_location_ping_latitude_too_low(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["latitude"] = -95.0  # < -90
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422

    def test_location_ping_longitude_too_high(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["longitude"] = -200.0  # < -180
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422

    def test_location_ping_longitude_too_low(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["longitude"] = 200.0  # > 180
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422

    def test_location_ping_negative_speed(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["speed_kmh"] = -5.0  # invalid
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 for negative speed, got {resp.status_code}: {resp.text}"
        )

    def test_location_ping_invalid_zone_status(self, client, tourist_auth_header):
        payload = valid_location_payload()
        payload["zone_status"] = "DANGER_ZONE_X"  # not in enum
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 422, (
            f"Expected 422 for invalid zone_status, got {resp.status_code}: {resp.text}"
        )

    def test_location_ping_all_valid_zone_statuses(self, client, tourist_auth_header):
        """All valid zone statuses should be accepted."""
        for status in ("SAFE", "CAUTION", "RESTRICTED", "UNKNOWN"):
            payload = valid_location_payload()
            payload["zone_status"] = status
            resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
            assert resp.status_code == 200, (
                f"zone_status={status} should be valid, got {resp.status_code}: {resp.text}"
            )


class TestLocationPingHappyPath:
    """Successful location pings."""

    def test_location_ping_valid_returns_200(self, client, tourist_auth_header):
        resp = client.post(
            "/location/ping",
            json=valid_location_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200, (
            f"Expected 200 for valid location ping, got {resp.status_code}: {resp.text}"
        )

    def test_location_ping_response_has_status_received(self, client, tourist_auth_header):
        resp = client.post(
            "/location/ping",
            json=valid_location_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body.get("status") == "received", (
            f"Expected status='received', got: {body}"
        )

    def test_location_ping_zero_speed_is_valid(self, client, tourist_auth_header):
        """Speed of 0 (standing still) should be accepted."""
        payload = valid_location_payload()
        payload["speed_kmh"] = 0.0
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 200

    def test_location_ping_uttarakhand_coordinates(self, client, tourist_auth_header):
        """Test with realistic Uttarakhand trekking GPS coordinates."""
        payload = valid_location_payload()
        payload["latitude"] = 30.7272
        payload["longitude"] = 79.5950  # Near Badrinath
        payload["speed_kmh"] = 3.5      # Trekking speed
        resp = client.post("/location/ping", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 200
