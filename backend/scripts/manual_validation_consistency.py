#!/usr/bin/env python3
import argparse
import datetime as dt
import json
import sqlite3
import sys
import time
import uuid

import requests


def fail(msg: str) -> None:
    print(f"[FAIL] {msg}")
    sys.exit(1)


def ok(msg: str) -> None:
    print(f"[PASS] {msg}")


def ensure_status(resp: requests.Response, allowed: set[int], context: str) -> None:
    if resp.status_code not in allowed:
        fail(f"{context}: status={resp.status_code}, body={resp.text}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Manual validation consistency helper")
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--db-path", default="backend/data/saferoute.db")
    args = parser.parse_args()

    base = args.base_url.rstrip("/")
    today = dt.date.today()
    unique_doc = str(uuid.uuid4().int % 10**12).zfill(12)

    # 1) health
    r = requests.get(f"{base}/health", timeout=10)
    ensure_status(r, {200}, "health")
    ok("Health endpoint is reachable")

    # 2) tourist register
    reg_payload = {
        "full_name": "Manual Validation Tourist",
        "document_type": "AADHAAR",
        "document_number": unique_doc,
        "emergency_contact_name": "QA Contact",
        "emergency_contact_phone": "9999999999",
        "trip_start_date": (today + dt.timedelta(days=1)).isoformat(),
        "trip_end_date": (today + dt.timedelta(days=10)).isoformat(),
        "destination_state": "Uttarakhand",
    }
    r = requests.post(f"{base}/v3/tourist/register", json=reg_payload, timeout=15)
    ensure_status(r, {200}, "tourist register")
    reg = r.json()
    tourist_id = reg["tourist"]["tourist_id"]
    token = reg["token"]
    refresh_token = reg["refresh_token"]
    tuid = reg["tourist"].get("tuid")
    ok(f"Tourist registered: {tourist_id}")

    # 3) login
    r = requests.post(f"{base}/v3/tourist/login", json={"tourist_id": tourist_id}, timeout=10)
    ensure_status(r, {200}, "tourist login")
    login_data = r.json()
    token = login_data.get("token", token)
    ok("Tourist login works")

    # 4) refresh
    r = requests.post(
        f"{base}/auth/refresh",
        headers={"Authorization": f"Bearer {refresh_token}"},
        timeout=10,
    )
    ensure_status(r, {200}, "token refresh")
    token = r.json().get("token", token)
    ok("Token refresh works")

    headers = {"Authorization": f"Bearer {token}"}

    # 5) location ping
    ping_payload = {
        "tourist_id": tourist_id,
        "latitude": 30.7272,
        "longitude": 79.5950,
        "speed_kmh": 2.0,
        "accuracy_meters": 5.0,
        "zone_status": "RESTRICTED",
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    r = requests.post(f"{base}/location/ping", headers=headers, json=ping_payload, timeout=10)
    ensure_status(r, {200, 201}, "location ping")
    ok("Location ping accepted")

    # 6) sos
    sos_payload = {
        "latitude": 30.7272,
        "longitude": 79.5950,
        "trigger_type": "MANUAL",
        "timestamp": dt.datetime.now(dt.timezone.utc).isoformat(),
    }
    r = requests.post(f"{base}/sos/trigger", headers=headers, json=sos_payload, timeout=10)
    ensure_status(r, {200, 201}, "sos trigger")
    ok("SOS trigger accepted")

    # 7) trip lifecycle
    now = dt.date.today()
    trip_payload = {
        "trip_start_date": now.isoformat() + "T00:00:00",
        "trip_end_date": (now + dt.timedelta(days=5)).isoformat() + "T23:59:00",
        "notes": "Manual validation flow",
        "stops": [
            {
                "name": "Kedarnath",
                "destination_state": "Uttarakhand",
                "visit_date_from": now.isoformat() + "T00:00:00",
                "visit_date_to": (now + dt.timedelta(days=2)).isoformat() + "T23:59:00",
                "order_index": 1,
                "center_lat": 30.735,
                "center_lng": 79.066,
            }
        ],
    }
    r = requests.post(f"{base}/v3/trips/", headers=headers, json=trip_payload, timeout=10)
    ensure_status(r, {200, 201}, "trip create")
    trip_id = r.json()["trip_id"]
    ok(f"Trip created: {trip_id}")

    r = requests.get(f"{base}/v3/trips/active", headers=headers, timeout=10)
    ensure_status(r, {200}, "trip active")
    active_trip = (r.json() or {}).get("active_trip") or {}
    if active_trip.get("trip_id") != trip_id:
        fail(f"active trip mismatch: expected={trip_id}, got={active_trip}")
    ok("Active trip read matches created trip")

    r = requests.put(f"{base}/v3/trips/{trip_id}/end", headers=headers, json={}, timeout=10)
    ensure_status(r, {200}, "trip end")
    ok("Trip end works")

    # 8) DB consistency
    con = sqlite3.connect(args.db_path)
    cur = con.cursor()
    cur.execute("SELECT tourist_id, tuid FROM tourists WHERE tourist_id = ?", (tourist_id,))
    tourist_row = cur.fetchone()
    if not tourist_row:
        fail("tourist record not found in DB")

    cur.execute(
        "SELECT tourist_id, zone_status FROM location_pings WHERE tourist_id = ? ORDER BY timestamp DESC LIMIT 1",
        (tourist_id,),
    )
    loc_row = cur.fetchone()
    if not loc_row:
        fail("location ping not found in DB")

    cur.execute(
        "SELECT tourist_id, trigger_type FROM sos_events WHERE tourist_id = ? ORDER BY timestamp DESC LIMIT 1",
        (tourist_id,),
    )
    sos_row = cur.fetchone()
    if not sos_row:
        fail("sos event not found in DB")

    cur.execute("SELECT trip_id, status FROM trips WHERE trip_id = ?", (trip_id,))
    trip_row = cur.fetchone()
    if not trip_row:
        fail("trip row not found in DB")

    con.close()
    ok("DB records found for tourist/location/sos/trip")

    print("\nSummary:")
    print(json.dumps({"tourist_id": tourist_id, "tuid": tuid, "trip_id": trip_id}, indent=2))
    print("[PASS] End-to-end consistency helper completed")


if __name__ == "__main__":
    main()
