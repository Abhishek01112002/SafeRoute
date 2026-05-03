# SafeRoute API Contracts

> **Primary Reference**: Interactive API docs are available at `http://localhost:8000/docs` when the backend is running.  
> This document provides a human-readable summary for mobile and dashboard team members.

---

## Base URL

| Environment | URL |
|---|---|
| Development | `http://10.0.2.2:8000` (Android Emulator) |
| Development | `http://localhost:8000` (Web/iOS Sim) |
| Production | `https://api.saferoute.app` |

## Authentication

All protected endpoints require a Bearer JWT token:
```
Authorization: Bearer <access_token>
```

All requests should include a correlation ID for tracing:
```
X-Correlation-ID: <uuid-v4>
```

---

## 👤 Tourist Endpoints

### `POST /v3/tourist/register`
Register a new tourist (JSON body).

**Auth**: Not required  
**Rate Limit**: 5/minute per IP

**Request Body**:
```json
{
  "full_name": "Rahul Sharma",
  "document_type": "AADHAAR",
  "document_number": "1234-5678-9012",
  "trip_start_date": "2025-06-01",
  "trip_end_date": "2025-06-15",
  "destination_state": "Uttarakhand",
  "emergency_contact_name": "Priya Sharma",
  "emergency_contact_phone": "+91-9876543210",
  "blood_group": "O+",
  "nationality": "IN",
  "selected_destinations": [
    {
      "destination_id": "UK_001",
      "name": "Valley of Flowers",
      "visit_date_from": "2025-06-03",
      "visit_date_to": "2025-06-05"
    }
  ]
}
```

**Success `201`**:
```json
{
  "tourist": { "tourist_id": "TID-2025-UK-A1B2C", "tuid": "TUID-...", "full_name": "..." },
  "token": "<jwt_access_token>",
  "refresh_token": "<jwt_refresh_token>",
  "expires_in": 3600
}
```

**Errors**:
- `409` — Document already registered (`{ "error": "Document already registered", "tourist_id": "TID-..." }`)
- `422` — Validation error (`{ "detail": [...] }`)
- `429` — Rate limit exceeded

---

### `POST /v3/tourist/login`
Retrieve tourist data by Tourist ID (acts as login).

**Auth**: Not required  
**Rate Limit**: 10/minute per IP, 5 failures → 15-min lockout

**Request Body**:
```json
{ "tourist_id": "TID-2025-UK-A1B2C" }
```

**Success `200`**:
```json
{
  "tourist": { "tourist_id": "...", "full_name": "...", ... },
  "token": "<access_token>",
  "refresh_token": "<refresh_token>",
  "expires_in": 3600
}
```

**Errors**:
- `400` — Invalid `tourist_id` format
- `404` — Tourist not found (`{ "error": "Tourist not found", "remaining_attempts": 4 }`)
- `429` — Account locked (`{ "retry_after_seconds": 900, "lockout_minutes": 15 }`)

---

### `GET /v3/tourist/photo/{tourist_id}`
Retrieve the tourist's profile photo.

**Auth**: Required (Bearer token)  
**Response**: `image/jpeg` binary

**Errors**: `404` — Tourist or photo not found

---

### `POST /v3/tourist/refresh-qr`
Refresh the tourist's QR JWT (call when within 30 days of expiry).

**Auth**: Required  
**Success `200`**:
```json
{ "qr_data": "<new_jwt>", "expires_at": "2026-01-01T00:00:00Z", "tuid": "TUID-..." }
```

---

## 🚨 SOS Endpoints

### `POST /sos/trigger`
Trigger an SOS alert for the authenticated tourist.

**Auth**: Required  
**Rate Limit**: 3/minute (life-critical — client retries 3× with no backoff)

**Request Body**:
```json
{
  "latitude": 30.7333,
  "longitude": 79.0667,
  "trigger_type": "MANUAL",
  "timestamp": "2025-06-03T10:30:00+05:30"
}
```

Valid `trigger_type` values: `MANUAL`, `AUTO_FALL`, `GEOFENCE_BREACH`

**Success `200`**:
```json
{
  "status": "alert_dispatched",
  "tourist_id": "TID-2025-UK-A1B2C",
  "timestamp": "2025-06-03T05:00:00+00:00",
  "dispatch": { "status": "delivered", "channel": "sms" }
}
```

**Errors**:
- `400` — Invalid coordinates or trigger type
- `400` — Timestamp too old (>10 min drift)
- `404` — Tourist not found

---

### `GET /sos/events`
List all SOS events (Authority only).

**Auth**: Required (Authority role)  
**Query Params**: `limit` (default 50), `offset` (default 0)

---

### `POST /sos/sync`
Sync a BLE Mesh-relayed SOS event.

**Auth**: Not required (cryptographic signature verified instead)

**Request Body**:
```json
{
  "tourist_id_suffix": "ABCD1234",
  "latitude": 30.7333,
  "longitude": 79.0667,
  "timestamp": "2025-06-03T10:30:00Z",
  "signature": "<base64_signature>"
}
```

---

## 📍 Location Endpoints

### `POST /location/ping`
Send a location update.

**Auth**: Required  
**Rate Limit**: 60/minute

**Request Body**:
```json
{
  "tourist_id": "TID-2025-UK-A1B2C",
  "latitude": 30.7333,
  "longitude": 79.0667,
  "speed_kmh": 12.5,
  "accuracy_meters": 5.2,
  "zone_status": "SAFE",
  "timestamp": "2025-06-03T10:30:00"
}
```

Valid `zone_status` values: `SAFE`, `CAUTION`, `RESTRICTED`, `UNKNOWN`

**Success `200`**: `{ "status": "received" }`

**Errors**: `422` — Validation failed (out-of-range lat/lng/speed)

---

## 🔐 Auth Endpoints

### `POST /auth/refresh`
Refresh an expired access token using a refresh token.

**Auth**: Refresh token in `Authorization: Bearer <refresh_token>` header

**Success `200`**:
```json
{
  "token": "<new_access_token>",
  "refresh_token": "<new_refresh_token>",
  "expires_in": 3600
}
```

**Errors**: `401` — Invalid or expired refresh token

---

## 🗺️ Zone Endpoints

### `GET /zones`
Fetch all active safety zones.

**Auth**: Required

**Success `200`**:
```json
[
  {
    "zone_id": "UK_ZONE_001",
    "name": "Valley of Flowers",
    "status": "SAFE",
    "latitude": 30.7,
    "longitude": 79.6,
    "radius_meters": 5000
  }
]
```

---

## 🏥 Health Endpoint

### `GET /health`
Check backend health. **No auth required.**

**Success `200`**:
```json
{ "status": "ok", "db": "connected", "version": "3.0.0" }
```

---

## 🏛️ Authority Endpoints

### `POST /authority/register`
Register a new authority account.

**Auth**: Not required (admin-initiated only in production)

### `POST /authority/login`
Login as an authority.

**Request Body**: `{ "email": "ranger@uk.gov.in", "password": "..." }`  
**Success `200`**: `{ "token": "...", "authority_id": "AUTH-...", "role": "authority" }`

---

## Error Response Format

All errors follow this format:
```json
{
  "detail": "Human-readable error message"
}
```
Or for validation errors (422):
```json
{
  "detail": [
    { "loc": ["body", "latitude"], "msg": "value is not a valid float", "type": "type_error.float" }
  ]
}
```
