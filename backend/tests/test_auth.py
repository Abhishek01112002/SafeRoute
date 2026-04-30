import pytest
from fastapi.testclient import TestClient
from backend.main import app
from backend.auth import create_token

client = TestClient(app)

def test_auth_roles():
    """Test that role-based endpoints properly restrict access."""
    tourist_token = create_token("T-123", "tourist")
    authority_token = create_token("A-123", "authority")

    # Tourist trying to access authority endpoint
    response = client.get("/destinations/states", headers={"Authorization": f"Bearer {tourist_token}"})
    # States endpoint doesn't require auth, so it should pass if we call a protected one
    
    response = client.post(
        "/destinations",
        json={"state": "Test", "name": "Test", "district": "Test", "center_lat": 0, "center_lng": 0},
        headers={"Authorization": f"Bearer {tourist_token}"}
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Authority role required"

def test_invalid_token():
    response = client.post(
        "/destinations",
        json={"state": "Test", "name": "Test", "district": "Test", "center_lat": 0, "center_lng": 0},
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code == 401
