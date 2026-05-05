# End-to-End Manual Validation Guide

This guide validates complete data flow across:
- Mobile app (real device)
- Backend API
- Dashboard
- Database

Use this after backend or integration changes.

## 1) Environment Setup

1. Start backend:
```powershell
cd D:\UKTravelTourism\Saferoute\backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

2. Start dashboard:
```powershell
cd D:\UKTravelTourism\Saferoute\dashboard
npm install
npm run dev
```

3. Confirm backend health from host:
```powershell
curl http://127.0.0.1:8000/health
```

4. Real-device networking:
- Connect phone and laptop to same Wi-Fi.
- Find host LAN IPv4:
```powershell
ipconfig
```
- Open `http://<LAN_IP>:8000/health` in phone browser and confirm `200`.
- Launch the mobile app with the same backend URL:
```powershell
cd D:\UKTravelTourism\Saferoute\mobile
flutter run -t lib/main_dev.dart --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000 --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000
```
- If the app was already installed before networking fixes, uninstall it from the device or run a full rebuild/reinstall instead of relying on hot reload.
- Ensure dashboard config points to the same backend base URL.

5. Optional clean start:
- Use unique document number per run.
- If needed, reset only test data records before run.

## 2) Mobile App Flow Checks

Record these values during testing:
- `tourist_id`
- `tuid`
- access `token`
- `refresh_token`
- `trip_id`(s)

### A) Tourist Registration (standard)
- Register tourist with valid future trip dates.
- Expected:
  - HTTP `200`
  - Response includes `tourist_id`, `token`, `refresh_token`, `expires_in`

### B) Tourist Registration (multipart/files)
- Submit valid profile photo and document scan.
- Expected:
  - HTTP `200`
  - Response contains persisted file/object key fields
  - No HTTP `500`

### C) Validation Behavior
- Submit multipart registration with past `trip_start_date`.
- Expected:
  - HTTP `422`
  - Structured `detail` JSON
  - No serialization/server crash

### D) Tourist Login
- Login using returned `tourist_id`.
- Expected:
  - HTTP `200`
  - Returns fresh `token` and `refresh_token`

### E) Location Pings
- Send pings with zone statuses: `SAFE`, `CAUTION`, `RESTRICTED`, `UNKNOWN`.
- Expected:
  - Accepted responses
  - Latest values visible in dashboard and DB

### F) SOS Trigger
- Trigger SOS with current timestamp.
- Expected:
  - Accepted response
  - Event appears in dashboard SOS queue
  - Persisted in DB

### G) Token Refresh Lifecycle
- Call protected endpoint with invalid token (expect `401` or `403`).
- Refresh with refresh token.
- Retry protected endpoint with new token.
- Expected:
  - Refresh succeeds and retry succeeds

### H) Trip Lifecycle
- Create trip with stops
- Verify active trip
- End trip
- Create planned trip
- Cancel planned trip
- Expected:
  - Correct transitions (ACTIVE -> COMPLETED)
  - Cancel allowed only when valid

## 3) Dashboard Validation

Verify each action from mobile appears in dashboard:

1. Tourist list/details:
- `tourist_id`, `tuid`, destination state, trip dates, emergency contact

2. Location panels:
- latest coordinates
- latest zone status matches mobile

3. SOS panels:
- event linked to correct tourist
- timestamp and status/dispatch fields present

4. Trip views:
- active trip while active
- completed/cancelled reflected after action

## 4) Database Validation

Use SQLite checks (adjust path if needed):
```powershell
cd D:\UKTravelTourism\Saferoute\backend
sqlite3 .\data\saferoute.db
```

Run these queries (replace placeholders):
```sql
-- Tourist master record
SELECT tourist_id, tuid, full_name, destination_state, created_at
FROM tourists
WHERE tourist_id = '<TOURIST_ID>';

-- Latest location rows
SELECT tourist_id, latitude, longitude, zone_status, timestamp
FROM location_pings
WHERE tourist_id = '<TOURIST_ID>'
ORDER BY timestamp DESC
LIMIT 20;

-- SOS rows
SELECT tourist_id, tuid, latitude, longitude, trigger_type, dispatch_status, timestamp
FROM sos_events
WHERE tourist_id = '<TOURIST_ID>'
ORDER BY timestamp DESC
LIMIT 20;

-- Trips
SELECT trip_id, tourist_id, status, trip_start_date, trip_end_date, created_at
FROM trips
WHERE tourist_id = '<TOURIST_ID>'
ORDER BY created_at DESC;
```

Consistency expectations:
- `tourist_id` and `tuid` match across tables.
- No orphan location/SOS rows.
- Timestamp behavior matches route rules (stale/future rejected).

## 5) Authority Auth Path Check

1. Register authority with strong password.
2. Login authority.
3. Refresh token.
4. Retry protected authority endpoint.

Expected:
- No password hash/verify failures.
- Login and refresh both succeed with valid credentials.

## 6) Automated Consistency Helper

Run:
```powershell
cd D:\UKTravelTourism\Saferoute
python backend\scripts\manual_validation_consistency.py --base-url http://127.0.0.1:8000
```

What it verifies:
- tourist register/login/refresh
- location ping accepted
- SOS accepted
- trip create/active/end
- DB rows exist for tourist/location/SOS/trip

## 7) Pass/Fail Gate

Pass the run only if all are true:
1. Mobile completes full flow without server crashes.
2. Dashboard reflects each action correctly.
3. DB records match API responses and IDs.
4. Error cases return `4xx`, not `500`.
5. Tourist + authority auth flows succeed.
6. Repeat with new identity and get same success.
