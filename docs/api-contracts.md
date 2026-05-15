# SafeRoute API Contracts

Last reviewed: 2026-05-16

Primary runtime reference: start the backend and open `http://localhost:8000/docs`.

This document summarizes the mounted routes in `backend/app/main.py` and the request patterns used by the Flutter app and React dashboard.

## Base URLs

| Client | Local URL |
| --- | --- |
| Dashboard / browser | `http://localhost:8000` |
| Android emulator | `http://10.0.2.2:8000` or a LAN IP configured with `SAFEROUTE_API_BASE_URL` |
| Physical device | `http://<LAN_IP>:8000` |
| Current deployed mobile default | `https://saferoute-backend-5ebu.onrender.com` |

Current `lib/main.dart` debug defaults are `http://10.43.205.74:8000` and `ws://10.43.205.74:8000`, but local developers should override them with their own LAN IP.

## Authentication

Protected endpoints require:

```http
Authorization: Bearer <access_token>
```

Refresh uses:

```http
Authorization: Bearer <refresh_token>
```

JWT access token lifetime defaults to `JWT_ACCESS_EXPIRY_MINUTES=60`. Refresh token lifetime defaults to `JWT_REFRESH_EXPIRY_DAYS=7`.

## Health

| Method | Path | Auth | Notes |
| --- | --- | --- | --- |
| `GET` | `/health` | None | Basic status and legacy cache counts |
| `GET` | `/live` | None | Liveness |
| `GET` | `/ready` | None | DB hard check, Redis/MinIO soft checks |
| `GET` | `/metrics` | None | Text metrics |
| `POST` | `/cleanup` | None | Location ping retention cleanup |

## Authority Auth

### `POST /auth/register/authority`

Registers an authority and returns tokens.

Required fields include `full_name`, `badge_id`, `email`, and `password`.

Password requirements:

- minimum 12 characters,
- uppercase,
- lowercase,
- digit,
- one of `@$!%*?&`.

### `POST /auth/login/authority`

```json
{
  "email": "ranger@example.gov",
  "password": "StrongPass123!"  <!-- pragma: allowlist secret -->
}
```

Returns authority data, `token`, `refresh_token`, and `expires_in`.

### `POST /auth/refresh`

Requires the refresh token in the bearer header and returns a fresh access and refresh token pair.

## Tourist Identity

### `POST /identity/verify`

Public, rate-limited duplicate-check endpoint. It returns no PII.

```json
{
  "document_type": "AADHAAR",
  "document_number": "123456789012",
  "date_of_birth": "1990-01-01",
  "nationality": "IN"
}
```

Response when not registered:

```json
{
  "already_registered": false,
  "prospective_tuid": "..."
}
```

## Tourist

### `POST /v3/tourist/register`

Public, rate-limited JSON tourist registration.

```json
{
  "full_name": "Rahul Sharma",
  "document_type": "AADHAAR",
  "document_number": "123456789012",
  "date_of_birth": "1990-01-01",
  "nationality": "IN",
  "emergency_contact_name": "Priya Sharma",
  "emergency_contact_phone": "+919876543210",
  "destination_state": "Meghalaya",
  "selected_destinations": [
    {
      "destination_id": "ML_CHE_001",
      "name": "Cherrapunji",
      "visit_date_from": "2026-06-01T00:00:00",
      "visit_date_to": "2026-06-03T00:00:00"
    }
  ],
  "blood_group": "O+"
}
```

Response includes:

- `tourist`,
- `token`,
- `refresh_token`,
- `expires_in`,
- `mesh_secret`,
- `mesh_key_version`,
- `mesh_key_expires_at`.

Duplicate documents return `409`.

### `POST /v3/tourist/register-multipart`

Multipart registration with `profile_photo` and `document_scan`. The current route still requires legacy trip fields (`trip_start_date`, `trip_end_date`, and `destination_state`) for this multipart path, even though new trip management should use `/v3/trips` after registration.

### `POST /v3/tourist/login`

```json
{
  "tourist_id": "TID-2026-ML-ABCDE"
}
```

Returns the tourist record, tokens, and mesh key fields. Tourist IDs must match `TID-YYYY-SS-XXXXX`.

Current brute-force behavior:

- 15 failed attempts,
- 5-minute attempt window,
- 15-minute lockout.

### `GET /v3/tourist/photo/{tourist_id}`

Authenticated tourist-only photo download.

### `POST /v3/tourist/mesh-key/rotate`

Authenticated. Returns a new `mesh_secret` and `mesh_key_version`; older keys enter grace.

### `POST /v3/tourist/refresh-qr`

Authenticated. Returns refreshed `qr_data`, `expires_at`, and `tuid`.

## Trips

All trip endpoints require a tourist bearer token.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v3/trips/` | Create a trip and mark old active trips completed |
| `GET` | `/v3/trips/active` | Return current active trip or `null` |
| `GET` | `/v3/trips/` | List trip history |
| `PUT` | `/v3/trips/{trip_id}/end` | Mark trip completed |
| `DELETE` | `/v3/trips/{trip_id}` | Mark trip cancelled |

Create body:

```json
{
  "trip_start_date": "2026-06-01T00:00:00",
  "trip_end_date": "2026-06-05T00:00:00",
  "notes": "Family trek",
  "stops": [
    {
      "destination_id": "ML_CHE_001",
      "name": "Cherrapunji",
      "destination_state": "Meghalaya",
      "visit_date_from": "2026-06-01T00:00:00",
      "visit_date_to": "2026-06-03T00:00:00",
      "order_index": 1,
      "center_lat": 25.2841,
      "center_lng": 91.7256
    }
  ]
}
```

## Groups

All group endpoints require a tourist bearer token.

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v3/groups` | Create a tourist group |
| `POST` | `/v3/groups/{invite_code}/join` | Join by invite code |
| `GET` | `/v3/groups/active` | Current active group |
| `GET` | `/v3/groups/{group_id}/members` | Member list and payload |
| `POST` | `/v3/groups/{group_id}/sharing` | Set `SHARING` or `PAUSED` |
| `POST` | `/v3/groups/{group_id}/leave` | Leave the group |

## Location

### `POST /location/ping`

Tourist authenticated.

```json
{
  "tourist_id": "TID-2026-ML-ABCDE",
  "tuid": "optional-tuid",
  "latitude": 25.2841,
  "longitude": 91.7256,
  "speed_kmh": 4.2,
  "accuracy_meters": 8.0,
  "zone_status": "SAFE",
  "timestamp": "2026-06-01T10:30:00"
}
```

Valid `zone_status`: `SAFE`, `CAUTION`, `RESTRICTED`, `UNKNOWN`.

## SOS

### `POST /sos/trigger`

Tourist authenticated, rate-limited to 3/minute. Returns `202`.

```json
{
  "latitude": 25.2841,
  "longitude": 91.7256,
  "location_unknown": false,
  "trigger_type": "MANUAL",
  "timestamp": "2026-06-01T10:30:00",
  "group_id": "optional-group-id",
  "idempotency_key": "optional-client-key"
}
```

Coordinates may both be omitted for a delayed offline SOS with unknown location. One missing coordinate is invalid.

Valid `trigger_type`: `MANUAL`, `AUTO_FALL`, `GEOFENCE_BREACH`.

Response includes `sos_id`, `queue_id`, `delivery_state`, `status_url`, and a public message.

### `POST /sos/trigger/relay`

Public cryptographic BLE relay endpoint. Optional bearer token identifies the relayer; the incident still belongs to the origin tourist.

```json
{
  "origin_tuid_suffix": "ABCD",
  "idempotency_hash": "a1b2c3d4e5f6",  <!-- pragma: allowlist secret -->
  "latitude": 25.2841,
  "longitude": 91.7256,
  "unix_minute": 29650000,
  "trigger_type": "MANUAL",
  "key_version": 1,
  "origin_signature": "abcd1234",
  "packet_id": "optional",
  "relay_path": [],
  "group_id": "optional"
}
```

### `GET /sos/{sos_id}/status`

Tourist authenticated. Only the owning tourist may read the status.

### Authority SOS Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/sos/events` | Paginated SOS list |
| `GET` | `/sos/events/{event_id}/delivery` | Queue and audit timeline |
| `POST` | `/sos/events/{event_id}/acknowledge` | Mark acknowledged |
| `POST` | `/sos/events/{event_id}/respond` | Mark resolved |

## Destinations

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/destinations/states` | None | Distinct states |
| `GET` | `/destinations` | None | Active destinations |
| `POST` | `/destinations` | Authority | Create destination |
| `GET` | `/destinations/{dest_id}/detail` | None | Destination detail, warnings, contacts |
| `GET` | `/destinations/{dest_id}/trail-graph` | None | Trail graph placeholder, empty when unavailable |
| `GET` | `/destinations/{state}` | None | Destinations filtered by state |
| `DELETE` | `/destinations/{dest_id}` | Authority | Deactivate destination |

## Zones

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `GET` | `/zones/active` | None | All active zones |
| `GET` | `/zones?destination_id=...` | None | Active zones for destination |
| `POST` | `/zones` | Authority | Create zone |
| `PUT` | `/zones/{zone_id}` | Authority | Update zone |
| `DELETE` | `/zones/{zone_id}` | Authority | Deactivate zone |

Valid zone types: `SAFE`, `CAUTION`, `RESTRICTED`.

Valid shapes: `CIRCLE`, `POLYGON`.

## Dashboard

Authority authenticated.

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/dashboard/metrics` | Aggregate counts |
| `GET` | `/dashboard/analytics` | Metrics, freshness, zone/SOS breakdowns, recent activity |
| `GET` | `/dashboard/tourists` | Paginated tourist list |
| `GET` | `/dashboard/locations` | Paginated last known locations |

## Authority Operations

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/authority/devices` | Register/update an authority FCM token |
| `GET` | `/authority/scan/{scanned_id}` | Scan TUID or legacy tourist ID, audit the scan, optionally return photo URL |

## Media

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/v3/media/upload-url` | Tourist | Presigned MinIO upload URL for JPEG/PNG/WebP up to 5 MB |
| `GET` | `/v3/media/download/{file_path:path}` | Tourist | Authenticated local upload download |

## Rooms

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/rooms/create` | Create room |
| `POST` | `/rooms/{room_id}/join` | Join room |
| `WS` | `/rooms/ws/{room_id}/{user_id}` | Room websocket |

## Onboarding And Well-Known

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/onboard/{token}` | Offline onboarding bundle by token |
| `GET` | `/onboard/preview/{destination_id}` | Generate preview onboarding QR bundle |
| `GET` | `/.well-known/qr-public-key` | Current QR verification public key |

## Error Shape

FastAPI validation errors use:

```json
{
  "detail": [
    {
      "loc": ["body", "field"],
      "msg": "error",
      "type": "value_error"
    }
  ]
}
```

Application errors usually use:

```json
{
  "detail": "Human-readable message"
}
```

Some duplicate/lockout paths return structured objects inside `detail`.
