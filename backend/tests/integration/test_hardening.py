import pytest
from fastapi.testclient import TestClient
import sys
import os
import datetime
import time

# Disable Redis for tests
os.environ["REDIS_URL"] = ""

# Add the current directory to sys.path so we can import 'app'
sys.path.append(os.getcwd())

from app import create_app
from app.services.jwt_service import create_jwt_token
from app.config import settings

app = create_app()
client = TestClient(app)

# Use a real tourist ID for testing
TEST_TOURIST_ID = "TID-TEST-TOURIST"

@pytest.fixture(autouse=True)
def setup_test_tourist():
    """Seed the database with a test tourist."""
    from app.db import sqlite_legacy
    sqlite_legacy.init_db()  # Ensure tables exist
    tourist_data = {
        "tourist_id": TEST_TOURIST_ID,
        "tuid": "TUID-TEST-1234567890",
        "full_name": "Test User",
        "nationality": "IN",
        "document_type": "AADHAAR",
        "trip_start_date": datetime.datetime.now().isoformat(),
        "trip_end_date": (datetime.datetime.now() + datetime.timedelta(days=7)).isoformat(),
        "destination_state": "Uttarakhand",
        "selected_destinations": []
    }
    sqlite_legacy.save_tourist(TEST_TOURIST_ID, tourist_data)
    sqlite_legacy.tourists_db[TEST_TOURIST_ID] = tourist_data
    yield
    # Cleanup if needed

@pytest.fixture
def auth_header():
    token = create_jwt_token(TEST_TOURIST_ID, role="tourist")
    return {"Authorization": f"Bearer {token}"}

def test_location_ping_invalid_lat(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 95.0,  # Invalid
        "longitude": 78.0,
        "speed_kmh": 10.0,
        "accuracy_meters": 5.0,
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/location/ping", json=payload, headers=auth_header)
    assert response.status_code == 422, f"Expected 422 but got {response.status_code}: {response.text}"

def test_location_ping_invalid_lng(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 30.0,
        "longitude": -190.0,  # Invalid
        "speed_kmh": 10.0,
        "accuracy_meters": 5.0,
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/location/ping", json=payload, headers=auth_header)
    assert response.status_code == 422, f"Expected 422 but got {response.status_code}: {response.text}"

def test_location_ping_negative_speed(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 30.0,
        "longitude": 78.0,
        "speed_kmh": -5.0,  # Invalid
        "accuracy_meters": 5.0,
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/location/ping", json=payload, headers=auth_header)
    assert response.status_code == 422, f"Expected 422 but got {response.status_code}: {response.text}"

def test_sos_trigger_invalid_coords(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 200.0,  # Invalid
        "longitude": 78.0,
        "trigger_type": "MANUAL",
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/sos/trigger", json=payload, headers=auth_header)
    # The SOS route does explicit validation before saving
    assert response.status_code == 400, f"Expected 400 but got {response.status_code}: {response.text}"

def test_sos_trigger_invalid_type(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 30.0,
        "longitude": 78.0,
        "trigger_type": "INVALID_TYPE",  # Invalid
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/sos/trigger", json=payload, headers=auth_header)
    assert response.status_code == 400, f"Expected 400 but got {response.status_code}: {response.text}"

def test_auth_refresh_expired_token():
    # Create an expired token
    token = create_jwt_token(
        TEST_TOURIST_ID,
        role="tourist",
        is_refresh=True,
        expires_delta=datetime.timedelta(seconds=-10)
    )
    headers = {"Authorization": f"Bearer {token}"}
    response = client.post("/auth/refresh", headers=headers)
    # verify_jwt_payload returns None for expired tokens,
    # and auth.py returns 401 "Invalid refresh token" for None payload.
    assert response.status_code == 401, f"Expected 401 but got {response.status_code}: {response.text}"
    assert "Invalid refresh token" in response.json().get("detail", "")

def test_location_ping_valid(auth_header):
    payload = {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 30.123,
        "longitude": 78.456,
        "speed_kmh": 12.5,
        "accuracy_meters": 3.2,
        "zone_status": "SAFE",
        "timestamp": datetime.datetime.now().isoformat()
    }
    response = client.post("/location/ping", json=payload, headers=auth_header)
    assert response.status_code == 200, f"Expected 200 but got {response.status_code}: {response.text}"
    assert response.json()["status"] == "received"
