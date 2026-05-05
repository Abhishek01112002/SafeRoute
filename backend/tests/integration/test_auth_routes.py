# backend/tests/test_auth_routes.py
#
# Tests for /auth/refresh endpoint.
# Covers: missing token, expired token, valid refresh token.

import pytest
import datetime


class TestAuthRefresh:
    """Tests for POST /auth/refresh."""

    def test_refresh_without_token_returns_401(self, client):
        """POST /auth/refresh with no auth header → 401 or 403."""
        resp = client.post("/auth/refresh")
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 without auth, got {resp.status_code}: {resp.text}"
        )

    def test_refresh_with_invalid_token_returns_401(self, client):
        """POST /auth/refresh with a garbage token → 401."""
        resp = client.post(
            "/auth/refresh",
            headers={"Authorization": "Bearer this.is.garbage"},
        )
        assert resp.status_code in (401, 403), (
            f"Expected 401/403 with garbage token, got {resp.status_code}: {resp.text}"
        )

    def test_refresh_with_expired_refresh_token_returns_401(
        self, client, expired_token_header
    ):
        """POST /auth/refresh with an expired refresh token → 401."""
        resp = client.post("/auth/refresh", headers=expired_token_header)
        assert resp.status_code == 401, (
            f"Expected 401 for expired token, got {resp.status_code}: {resp.text}"
        )

    def test_refresh_expired_token_returns_invalid_message(
        self, client, expired_token_header
    ):
        """Error message should confirm token is invalid."""
        resp = client.post("/auth/refresh", headers=expired_token_header)
        body = resp.json()
        detail = body.get("detail", "").lower()
        assert "invalid" in detail or "expired" in detail or "token" in detail, (
            f"Expected 'invalid/expired/token' in error detail, got: {detail}"
        )

    def test_refresh_with_valid_refresh_token_returns_200(self, client):
        """POST /auth/refresh with a valid refresh token → 200 with new tokens."""
        from app.services.jwt_service import create_jwt_token
        from tests.conftest import TEST_TOURIST_ID

        # Create a valid refresh token
        refresh_token = create_jwt_token(
            TEST_TOURIST_ID,
            role="tourist",
            is_refresh=True,
        )
        resp = client.post(
            "/auth/refresh",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )
        assert resp.status_code == 200, (
            f"Expected 200 for valid refresh token, got {resp.status_code}: {resp.text}"
        )

    def test_refresh_response_has_new_access_token(self, client):
        """Refresh response must include a new access token."""
        from app.services.jwt_service import create_jwt_token
        from tests.conftest import TEST_TOURIST_ID

        refresh_token = create_jwt_token(
            TEST_TOURIST_ID,
            role="tourist",
            is_refresh=True,
        )
        resp = client.post(
            "/auth/refresh",
            headers={"Authorization": f"Bearer {refresh_token}"},
        )
        assert resp.status_code == 200
        body = resp.json()
        assert "token" in body or "access_token" in body, (
            f"Response missing access token field: {body}"
        )
