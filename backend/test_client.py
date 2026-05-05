from fastapi.testclient import TestClient
from main import app
import datetime
import json
import uuid

today = datetime.date.today()

payload = {
    "full_name": "Test Tourist",
    "document_type": "AADHAAR",
    "document_number": str(uuid.uuid4().int % 10**12).zfill(12),
    "emergency_contact_name": "Mom",
    "emergency_contact_phone": "1234567890",
    "trip_start_date": (today + datetime.timedelta(days=1)).isoformat(),
    "trip_end_date": (today + datetime.timedelta(days=15)).isoformat(),
    "destination_state": "Uttarakhand"
}

with TestClient(app) as client:
    response = client.post("/v3/tourist/register", json=payload)
    print("STATUS CODE:", response.status_code)
    print("RESPONSE:", response.json())
