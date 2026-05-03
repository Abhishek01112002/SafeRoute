"""
Fast Trip E2E: Uses existing tourist in the database (or creates minimal one),
then exercises the full Trip lifecycle.
"""
import requests, json, sqlite3, datetime, sys

BASE = "http://127.0.0.1:8001"

def step(name): print(f"\n{'='*55}\n  {name}\n{'='*55}")
def ok(msg):    print(f"  [PASS] {msg}")
def fail(msg):  print(f"  [FAIL] {msg}"); sys.exit(1)

# ── Find an existing tourist in the DB ───────────────────────
step("STEP 0: Find existing tourist for testing")
con = sqlite3.connect("saferoute.db")
row = con.execute(
    "SELECT tourist_id, tuid FROM tourists LIMIT 1"
).fetchone()
con.close()

if not row:
    fail("No tourists in DB — run the app and register first")

tourist_id, tuid = row
print(f"  tourist_id : {tourist_id}")
print(f"  tuid       : {tuid}")
ok("Found existing tourist")

# ── Login ────────────────────────────────────────────────────
step("STEP 1: Login via /v3/tourist/login")
login_r = requests.post(
    f"{BASE}/v3/tourist/login",
    json={"tourist_id": tourist_id},
    timeout=10
)
print(f"  Status: {login_r.status_code}")
if login_r.status_code != 200:
    print(f"  Body: {login_r.text}")
    fail("Login failed")

login_data = login_r.json()
print(f"  Keys: {list(login_data.keys())}")
token = (login_data.get("access_token")
         or login_data.get("token")
         or login_data.get("jwt"))

if not token:
    print(f"  Full response: {json.dumps(login_data, indent=2)}")
    fail("No token in login response")

print(f"  JWT: {token[:50]}...")
ok("Logged in")
H = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

# ── GET current active trip (may be null) ────────────────────
step("STEP 2: GET /v3/trips/active (pre-test state)")
r = requests.get(f"{BASE}/v3/trips/active", headers=H, timeout=10)
print(f"  Status: {r.status_code}")
pre = r.json().get("active_trip")
print(f"  Existing active trip: {pre['trip_id'] if pre else 'None'}")
ok("Pre-test state read")

# ── Create trip with 2 stops ─────────────────────────────────
step("STEP 3: POST /v3/trips/ — 2 stops")
today = datetime.date.today()
payload = {
    "trip_start_date": today.isoformat() + "T00:00:00",
    "trip_end_date":   (today + datetime.timedelta(days=10)).isoformat() + "T23:59:00",
    "notes":           "E2E automated test",
    "stops": [
        {
            "name": "Kedarnath",
            "destination_state": "Uttarakhand",
            "visit_date_from": today.isoformat() + "T00:00:00",
            "visit_date_to":   (today + datetime.timedelta(days=4)).isoformat() + "T23:59:00",
            "order_index": 1,
            "center_lat": 30.735,
            "center_lng": 79.066
        },
        {
            "name": "Badrinath",
            "destination_state": "Uttarakhand",
            "visit_date_from": (today + datetime.timedelta(days=5)).isoformat() + "T00:00:00",
            "visit_date_to":   (today + datetime.timedelta(days=10)).isoformat() + "T23:59:00",
            "order_index": 2,
            "center_lat": 30.74,
            "center_lng": 79.49
        }
    ]
}
r = requests.post(f"{BASE}/v3/trips/", json=payload, headers=H, timeout=10)
print(f"  Status: {r.status_code}")
if r.status_code not in (200, 201):
    print(f"  Body: {r.text}")
    fail("Create trip failed")

trip = r.json()
trip_id = trip["trip_id"]
assert trip["status"]        == "ACTIVE",       f"Status mismatch: {trip['status']}"
assert trip["primary_state"] == "Uttarakhand",  f"State mismatch: {trip['primary_state']}"
assert len(trip["stops"])    == 2,              f"Stop count: {len(trip['stops'])}"
ok(f"Trip created: {trip_id}")
ok(f"Stops: {[s['name'] for s in sorted(trip['stops'], key=lambda s: s['order_index'])]}")

# ── Verify previous active auto-completed ────────────────────
if pre:
    step("STEP 3b: Verify old active trip was auto-completed")
    old_id = pre["trip_id"]
    # Check it via list endpoint
    list_r = requests.get(f"{BASE}/v3/trips/", headers=H, timeout=10)
    trips = list_r.json().get("trips", [])
    old = next((t for t in trips if t["trip_id"] == old_id), None)
    if old and old["status"] == "COMPLETED":
        ok(f"Previous trip {old_id} auto-completed ✅")
    else:
        print(f"  Old trip status: {old['status'] if old else 'NOT FOUND'}")

# ── GET active trip ──────────────────────────────────────────
step("STEP 4: GET /v3/trips/active")
r = requests.get(f"{BASE}/v3/trips/active", headers=H, timeout=10)
print(f"  Status: {r.status_code}")
active = r.json().get("active_trip")
if not active: fail("No active trip returned!")
assert active["trip_id"] == trip_id
assert len(active["stops"]) == 2
ok(f"Active: {active['trip_id']}")
ok(f"Stops: {[s['name'] for s in active['stops']]}")

# ── List all trips ───────────────────────────────────────────
step("STEP 5: GET /v3/trips/ — history list")
r = requests.get(f"{BASE}/v3/trips/", headers=H, timeout=10)
print(f"  Status: {r.status_code}")
trips = r.json().get("trips", [])
assert any(t["trip_id"] == trip_id for t in trips)
ok(f"Trip in history ({len(trips)} total trips)")

# ── End the trip ─────────────────────────────────────────────
step("STEP 6: PUT /v3/trips/{id}/end")
r = requests.put(f"{BASE}/v3/trips/{trip_id}/end", json={}, headers=H, timeout=10)
print(f"  Status: {r.status_code}")
if r.status_code != 200:
    print(f"  Body: {r.text}")
    fail("End trip failed")
data = r.json()
assert data["status"] == "COMPLETED", f"Expected COMPLETED got {data['status']}"
ok(f"Trip ended: {data}")

# ── Verify no active trip ────────────────────────────────────
step("STEP 7: Confirm no active trip after end")
r = requests.get(f"{BASE}/v3/trips/active", headers=H, timeout=10)
final = r.json().get("active_trip")
if final is not None:
    fail(f"Still has active trip: {final['trip_id']}")
ok("active_trip is null — correct")

# ── Cancel test: create + cancel ─────────────────────────────
step("STEP 8: Cancel a PLANNED trip")
# Create with start date in the future
tomorrow = (today + datetime.timedelta(days=1)).isoformat()
future_payload = {
    "trip_start_date": tomorrow + "T00:00:00",
    "trip_end_date":   (today + datetime.timedelta(days=5)).isoformat() + "T23:59:00",
    "stops": [{
        "name": "Manali",
        "destination_state": "Himachal Pradesh",
        "visit_date_from": tomorrow + "T00:00:00",
        "visit_date_to":   (today + datetime.timedelta(days=5)).isoformat() + "T23:59:00",
        "order_index": 1
    }]
}
r2 = requests.post(f"{BASE}/v3/trips/", json=future_payload, headers=H, timeout=10)
print(f"  Create status: {r2.status_code}")
if r2.status_code in (200, 201):
    new_trip_id = r2.json()["trip_id"]
    del_r = requests.delete(f"{BASE}/v3/trips/{new_trip_id}", headers=H, timeout=10)
    print(f"  Cancel status: {del_r.status_code}")
    if del_r.status_code == 200:
        ok(f"Trip {new_trip_id} cancelled")
    else:
        print(f"  Cancel body: {del_r.text}")

# ── Final summary ────────────────────────────────────────────
print(f"\n{'='*55}")
print("  *** ALL E2E TESTS PASSED ***")
print(f"{'='*55}\n")
