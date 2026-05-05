import pytest
import datetime
import time

@pytest.mark.asyncio
async def test_full_trip_lifecycle(client):
    """
    E2E Test: Exercises the full Trip lifecycle using the test client.
    1. Register a tourist
    2. Login
    3. Create a trip with stops
    4. Verify active trip
    5. End the trip
    """
    # Create a unique 12-digit number for Aadhaar validation
    unique_id = f"11{int(time.time())}"[-12:]

    # --- 1. Registration & Login ---
    reg_payload = {
        "full_name": "E2E Trip Tester",
        "document_type": "AADHAAR",
        "document_number": unique_id,
        "emergency_contact_name": "Emergency Person",
        "emergency_contact_phone": "9876543210",
        "trip_start_date": "2026-06-01",
        "trip_end_date": "2026-06-15",
        "destination_state": "Uttarakhand"
    }
    reg_resp = client.post("/v3/tourist/register", json=reg_payload)
    assert reg_resp.status_code == 200

    data = reg_resp.json()
    token = data["token"]
    headers = {"Authorization": f"Bearer {token}"}

    # --- 2. Create a Trip ---
    today = datetime.date.today()
    trip_payload = {
        "trip_start_date": today.isoformat() + "T00:00:00",
        "trip_end_date": (today + datetime.timedelta(days=10)).isoformat() + "T23:59:00",
        "notes": "E2E automated test",
        "stops": [
            {
                "name": "Kedarnath",
                "destination_state": "Uttarakhand",
                "visit_date_from": today.isoformat() + "T00:00:00",
                "visit_date_to": (today + datetime.timedelta(days=4)).isoformat() + "T23:59:00",
                "order_index": 1,
                "center_lat": 30.735,
                "center_lng": 79.066
            }
        ]
    }

    create_resp = client.post("/v3/trips/", json=trip_payload, headers=headers)
    assert create_resp.status_code in [200, 201]
    trip_id = create_resp.json()["trip_id"]

    # --- 3. Verify Active Trip ---
    active_resp = client.get("/v3/trips/active", headers=headers)
    assert active_resp.status_code == 200
    assert active_resp.json()["active_trip"]["trip_id"] == trip_id

    # --- 4. End the Trip ---
    end_resp = client.put(f"/v3/trips/{trip_id}/end", json={}, headers=headers)
    assert end_resp.status_code == 200
    assert end_resp.json()["status"] == "COMPLETED"
