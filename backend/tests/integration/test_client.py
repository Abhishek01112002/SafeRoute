from fastapi.testclient import TestClient
from main import app
import json

client = TestClient(app)

payload = {
    "full_name": "Test Tourist",
    "document_type": "AADHAAR",
    "document_number": "999988887777",
    "emergency_contact_name": "Mom",
    "emergency_contact_phone": "1234567890",
    "trip_start_date": "2026-05-01",
    "trip_end_date": "2026-05-15",
    "destination_state": "Uttarakhand"
}

response = client.post("/v3/tourist/register", json=payload)
print("STATUS CODE:", response.status_code)
print("RESPONSE:", response.json())
