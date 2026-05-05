import pytest
from fastapi.testclient import TestClient
import sys
import os
sys.path.append(os.getcwd())

from app.main import app
from app.services.jwt_service import create_jwt_token as create_token

client = TestClient(app)

def test_auth_roles():
    """Test that role-based endpoints properly restrict access."""
    tourist_token = create_token("T-123", role="tourist")

    # Tourist trying to access authority endpoint (/sos/events)
    response = client.get(
        "/sos/events",
        headers={"Authorization": f"Bearer {tourist_token}"}
    )
    assert response.status_code == 403
    assert response.json()["detail"] == "Authority token required"

def test_invalid_token():
    # Attempt to access protected endpoint with garbage token
    response = client.get(
        "/sos/events",
        headers={"Authorization": "Bearer invalid_token"}
    )
    assert response.status_code == 401
