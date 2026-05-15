# SafeRoute API Quick Reference

Last reviewed: 2026-05-16

This internal quick reference has been refreshed from `backend/app/main.py`. For fuller request and response examples, use `../api-contracts.md`.

## Public / Operational

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/health` | Basic app health |
| `GET` | `/live` | Liveness probe |
| `GET` | `/ready` | DB readiness plus Redis/MinIO soft checks |
| `GET` | `/metrics` | Text metrics |
| `POST` | `/identity/verify` | Public duplicate-check identity verification |
| `GET` | `/destinations` | Active destinations |
| `GET` | `/destinations/states` | Active destination states |
| `GET` | `/destinations/{dest_id}/detail` | Destination detail |
| `GET` | `/destinations/{dest_id}/trail-graph` | Offline graph placeholder |
| `GET` | `/zones/active` | All active zones |
| `GET` | `/zones?destination_id=...` | Destination zones |
| `POST` | `/sos/trigger/relay` | BLE relay SOS packet submission |
| `GET` | `/.well-known/qr-public-key` | QR verification public key |

## Auth

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/auth/register/authority` | None | Register authority and return tokens |
| `POST` | `/auth/login/authority` | None | Authority login |
| `POST` | `/auth/refresh` | Refresh token | Rotate access/refresh tokens |

## Tourist

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/v3/tourist/register` | None | JSON registration |
| `POST` | `/v3/tourist/register-multipart` | None | Registration with files |
| `POST` | `/v3/tourist/login` | None | Tourist login by TID |
| `GET` | `/v3/tourist/photo/{tourist_id}` | Tourist | Own profile photo |
| `POST` | `/v3/tourist/mesh-key/rotate` | Tourist | Rotate BLE mesh key |
| `POST` | `/v3/tourist/refresh-qr` | Tourist | Refresh QR JWT |

## Trips And Groups

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/v3/trips/` | Tourist | Create active trip |
| `GET` | `/v3/trips/active` | Tourist | Active trip |
| `GET` | `/v3/trips/` | Tourist | Trip history |
| `PUT` | `/v3/trips/{trip_id}/end` | Tourist | Complete trip |
| `DELETE` | `/v3/trips/{trip_id}` | Tourist | Cancel trip |
| `POST` | `/v3/groups` | Tourist | Create group |
| `POST` | `/v3/groups/{invite_code}/join` | Tourist | Join group |
| `GET` | `/v3/groups/active` | Tourist | Active group |
| `GET` | `/v3/groups/{group_id}/members` | Tourist | Members |
| `POST` | `/v3/groups/{group_id}/sharing` | Tourist | Pause/resume sharing |
| `POST` | `/v3/groups/{group_id}/leave` | Tourist | Leave group |

## Location And SOS

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/location/ping` | Tourist | Store location ping |
| `POST` | `/sos/trigger` | Tourist | Queue direct SOS |
| `GET` | `/sos/{sos_id}/status` | Owning tourist | SOS status |
| `GET` | `/sos/events` | Authority | Paginated SOS events |
| `GET` | `/sos/events/{event_id}/delivery` | Authority | Queue/audit timeline |
| `POST` | `/sos/events/{event_id}/acknowledge` | Authority | Acknowledge |
| `POST` | `/sos/events/{event_id}/respond` | Authority | Resolve |

## Authority And Dashboard

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/authority/devices` | Authority | Register FCM token |
| `GET` | `/authority/scan/{scanned_id}` | Authority | Scan TUID or TID |
| `GET` | `/dashboard/metrics` | Authority | Counts |
| `GET` | `/dashboard/analytics` | Authority | Full dashboard rollup |
| `GET` | `/dashboard/tourists` | Authority | Tourist list |
| `GET` | `/dashboard/locations` | Authority | Last known locations |

## Zone And Destination Mutations

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/destinations` | Authority | Create destination |
| `DELETE` | `/destinations/{dest_id}` | Authority | Deactivate destination |
| `POST` | `/zones` | Authority | Create zone |
| `PUT` | `/zones/{zone_id}` | Authority | Update zone |
| `DELETE` | `/zones/{zone_id}` | Authority | Deactivate zone |

## Media And Rooms

| Method | Path | Auth | Purpose |
| --- | --- | --- | --- |
| `POST` | `/v3/media/upload-url` | Tourist | MinIO upload URL |
| `GET` | `/v3/media/download/{file_path}` | Tourist | Local upload download |
| `POST` | `/rooms/create` | None | Create room |
| `POST` | `/rooms/{room_id}/join` | None | Join room |
| `WS` | `/rooms/ws/{room_id}/{user_id}` | None | Room websocket |

## Known Contract Details

- API version shown by FastAPI app: `3.1.0`.
- Direct SOS returns `202` and a queued status payload.
- Dashboard polling interval is currently 10 seconds.
- `READ_FROM_PG` must not be true unless `ENABLE_PG` is true.
- Default dev DB is `sqlite+aiosqlite:///./saferoute.db`.
