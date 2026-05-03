# backend/tests/test_sos_routes.py
#
# Tests for /sos/trigger and /sos/sync endpoints.
# Covers: auth enforcement, coordinate validation,
# trigger type validation, timestamp validation, and happy path.

import pytest
import datetime
from tests.conftest import valid_sos_payload, TEST_TOURIST_ID


class TestSosTriggerAuth:
    """Auth enforcement tests."""

    def test_sos_trigger_requires_auth(self, client):
        """POST /sos/trigger without token → 401 or 403."""
        resp = client.post("/sos/trigger", json=valid_sos_payload())
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 without auth, got {resp.status_code}: {resp.text}"
        )

    def test_sos_trigger_with_invalid_token(self, client):
        """POST /sos/trigger with garbage token → 401 or 403."""
        resp = client.post(
            "/sos/trigger",
            json=valid_sos_payload(),
            headers={"Authorization": "Bearer totally.not.a.token"},
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 with invalid token, got {resp.status_code}: {resp.text}"
        )


class TestSosTriggerValidation:
    """Input validation tests."""

    def test_sos_trigger_invalid_latitude_too_high(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        payload["latitude"] = 91.0  # > 90
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400, (
            f"Expected 400 for lat=91, got {resp.status_code}: {resp.text}"
        )

    def test_sos_trigger_invalid_latitude_too_low(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        payload["latitude"] = -91.0  # < -90
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400

    def test_sos_trigger_invalid_longitude_too_high(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        payload["longitude"] = 181.0  # > 180
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400

    def test_sos_trigger_invalid_longitude_too_low(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        payload["longitude"] = -181.0  # < -180
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400

    def test_sos_trigger_missing_latitude(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        del payload["latitude"]
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400

    def test_sos_trigger_missing_longitude(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        del payload["longitude"]
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400

    def test_sos_trigger_invalid_trigger_type(self, client, tourist_auth_header):
        payload = valid_sos_payload()
        payload["trigger_type"] = "INVALID_TYPE"
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400, (
            f"Expected 400 for invalid trigger_type, got {resp.status_code}: {resp.text}"
        )

    def test_sos_trigger_all_valid_trigger_types(self, client, tourist_auth_header):
        """All three valid trigger types should be accepted."""
        for trigger_type in ("MANUAL", "AUTO_FALL", "GEOFENCE_BREACH"):
            payload = valid_sos_payload()
            payload["trigger_type"] = trigger_type
            resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
            assert resp.status_code == 200, (
                f"trigger_type={trigger_type} should be valid, got {resp.status_code}: {resp.text}"
            )

    def test_sos_trigger_stale_timestamp(self, client, tourist_auth_header):
        """A timestamp more than 10 minutes old should be rejected."""
        payload = valid_sos_payload()
        stale_time = datetime.datetime.now() - datetime.timedelta(minutes=15)
        payload["timestamp"] = stale_time.isoformat()
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400, (
            f"Expected 400 for stale timestamp, got {resp.status_code}: {resp.text}"
        )

    def test_sos_trigger_future_timestamp(self, client, tourist_auth_header):
        """A timestamp far in the future should be rejected."""
        payload = valid_sos_payload()
        future_time = datetime.datetime.now() + datetime.timedelta(minutes=15)
        payload["timestamp"] = future_time.isoformat()
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 400, (
            f"Expected 400 for future timestamp, got {resp.status_code}: {resp.text}"
        )


class TestSosTriggerHappyPath:
    """Successful SOS trigger."""

    def test_sos_trigger_valid_returns_200(self, client, tourist_auth_header):
        resp = client.post(
            "/sos/trigger",
            json=valid_sos_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200, (
            f"Expected 200 for valid SOS trigger, got {resp.status_code}: {resp.text}"
        )

    def test_sos_trigger_response_has_status_field(self, client, tourist_auth_header):
        resp = client.post(
            "/sos/trigger",
            json=valid_sos_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "status" in body, f"Response missing 'status' field: {body}"

    def test_sos_trigger_response_has_tourist_id(self, client, tourist_auth_header):
        resp = client.post(
            "/sos/trigger",
            json=valid_sos_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "tourist_id" in body, f"Response missing 'tourist_id': {body}"
        assert body["tourist_id"] == TEST_TOURIST_ID

    def test_sos_trigger_response_has_timestamp(self, client, tourist_auth_header):
        resp = client.post(
            "/sos/trigger",
            json=valid_sos_payload(),
            headers=tourist_auth_header,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "timestamp" in body, f"Response missing 'timestamp': {body}"

    def test_sos_trigger_uttarakhand_coordinates(self, client, tourist_auth_header):
        """Test with realistic Uttarakhand GPS coordinates."""
        payload = valid_sos_payload()
        payload["latitude"] = 30.3165
        payload["longitude"] = 78.0322
        resp = client.post("/sos/trigger", json=payload, headers=tourist_auth_header)
        assert resp.status_code == 200
