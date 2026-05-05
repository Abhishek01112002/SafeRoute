import time
from app.db.sqlite_legacy import tourists_db

def test_tourist_registration_success(client):
    """
    Test that a new tourist can be successfully registered via the API.
    Uses a unique 12-digit document number to satisfy Aadhaar validation.
    """
    # Create a unique 12-digit number (Aadhaar requirement)
    # time.time() is ~10 digits, we pad with '00' to make it 12
    unique_id = f"00{int(time.time())}"[-12:]

    payload = {
        "full_name": "Integration Tester",
        "document_type": "AADHAAR",
        "document_number": unique_id,
        "emergency_contact_name": "Emergency Person",
        "emergency_contact_phone": "9876543210",
        "trip_start_date": "2026-06-01",
        "trip_end_date": "2026-06-15",
        "destination_state": "Uttarakhand"
    }

    response = client.post("/v3/tourist/register", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert "token" in data
    assert data["tourist"]["full_name"] == "Integration Tester"

    tourist_id = data["tourist"]["tourist_id"]
    assert tourist_id in tourists_db
