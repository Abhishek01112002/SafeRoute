"""Quick probe: find the correct register and login endpoints."""
import requests, json, uuid

BASE = "http://localhost:8001"

# 1. Probe register
print("=== PROBE REGISTER ===")
r = requests.post(f"{BASE}/v3/tourist/register", json={
    "full_name": "Probe Tourist",
    "document_type": "AADHAAR",
    "document_number": str(uuid.uuid4().int)[:12],
    "emergency_contact_name": "EC",
    "emergency_contact_phone": "+91-9999999999",
    "blood_group": "O+",
    "date_of_birth": "1995-01-01",
    "nationality": "IN"
}, timeout=10)
print(f"Status: {r.status_code}")
print(json.dumps(r.json(), indent=2))
