import pytest

def test_api_health_check(client):
    response = client.get("/health")
    assert response.status_code == 200

def test_api_zones_active_list(client):
    # Use /zones/active to avoid mandatory destination_id query parameter
    response = client.get("/zones/active")
    assert response.status_code == 200

def test_api_destinations_list(client):
    # Route is /destinations
    response = client.get("/destinations")
    assert response.status_code == 200

def test_api_tourist_login_format_check(client):
    # Testing with a validly formatted but non-existent ID should return 404
    # Format: TID-YYYY-SS-XXXXX
    payload = {"tourist_id": "TID-2026-UK-NULL0"}
    response = client.post("/v3/tourist/login", json=payload)
    assert response.status_code == 404

def test_api_authority_login_unauthorized(client):
    # Actual route is /auth/login/authority, and it expects 'email' and 'password'
    payload = {"email": "bad@authority.com", "password": "wrong"}  # pragma: allowlist secret
    response = client.post("/auth/login/authority", json=payload)
    assert response.status_code == 401
