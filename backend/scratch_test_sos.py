import requests
import json
import time
import sys

# Ensure stdout uses UTF-8 to avoid charmap errors on Windows
if sys.platform == "win32":
    import codecs
    sys.stdout = codecs.getwriter("utf-8")(sys.stdout.detach())

BASE_URL = "http://127.0.0.1:8000"

def test_hardened_sos_flow():
    # 1. Test Structured 422 (Past Date)
    print("\n--- Testing Structured 422 (Invalid Date) ---")
    reg_payload = {
        "full_name": "Test User",
        "document_type": "AADHAAR",
        "document_number": "123456789012",
        "emergency_contact_name": "Emergency",
        "emergency_contact_phone": "112",
        "trip_start_date": "2020-01-01", # PAST DATE
        "trip_end_date": "2026-05-20",
        "destination_state": "Uttarakhand",
        "blood_group": "O+",
        "date_of_birth": "1990-01-01",
        "nationality": "IN"
    }
    files = {
        "profile_photo": ("photo.jpg", b"fake-photo-content", "image/jpeg"),
        "document_scan": ("doc.pdf", b"fake-doc-content", "application/pdf")
    }

    response = requests.post(f"{BASE_URL}/v3/tourist/register-multipart", data=reg_payload, files=files)
    print(f"Status: {response.status_code}")
    if response.status_code == 422:
        print("[OK] Received structured 422 as expected")
        try:
            detail = response.json().get("detail")
            print(f"Error Detail: {json.dumps(detail, indent=2)}")
        except:
            print(f"Raw Detail: {response.text}")
    else:
        print(f"[FAIL] Expected 422 but got {response.status_code}")

    # 2. Register properly
    print("\n--- Registering Properly ---")
    reg_payload["trip_start_date"] = "2026-12-01"
    # Use unique doc number to avoid 409 Conflict if possible
    reg_payload["document_number"] = str(int(time.time()))[:12].zfill(12)

    response = requests.post(f"{BASE_URL}/v3/tourist/register-multipart", data=reg_payload, files=files)

    if response.status_code != 200:
        print(f"[FAIL] Failed to register: {response.text}")
        return

    data = response.json()
    token = data["token"]
    refresh_token = data["refresh_token"]
    print("[OK] Registered successfully")

    # 3. Test Token Refresh Lifecycle
    print("\n--- Testing Token Refresh Lifecycle ---")
    # Simulate an expired token by sending a garbage one to get 401
    bad_headers = {"Authorization": "Bearer garbage.token.here"}
    sos_payload = {
        "latitude": 30.3165, "longitude": 78.0322,
        "trigger_type": "MANUAL", "timestamp": "2026-05-03T13:00:00Z"
    }

    print("Sending SOS with invalid token...")
    response = requests.post(f"{BASE_URL}/sos/trigger", headers=bad_headers, json=sos_payload)
    print(f"Initial Status (Expected 401): {response.status_code}")

    if response.status_code == 401:
        print("Received 401. Attempting manual refresh in script...")
        refresh_headers = {"Authorization": f"Bearer {refresh_token}"}
        refresh_resp = requests.post(f"{BASE_URL}/auth/refresh", headers=refresh_headers)

        if refresh_resp.status_code == 200:
            new_token = refresh_resp.json()["token"]
            print("[OK] Token refreshed successfully")

            # 4. Retry SOS with new token
            print("Retrying SOS with new token...")
            good_headers = {"Authorization": f"Bearer {new_token}"}
            final_resp = requests.post(f"{BASE_URL}/sos/trigger", headers=good_headers, json=sos_payload)
            print(f"Final SOS Status: {final_resp.status_code}")
            if final_resp.status_code == 200:
                print("[OK] SOS trigger successful after refresh!")
            else:
                print(f"[FAIL] SOS failed with refreshed token: {final_resp.text}")
        else:
            print(f"[FAIL] Refresh failed: {refresh_resp.text}")

if __name__ == "__main__":
    test_hardened_sos_flow()
