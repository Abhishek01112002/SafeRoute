# SafeRoute Backend Quick Start

Last reviewed: 2026-05-16

This guide reflects the current SafeRoute API v3.1.0 backend in `backend/app`. Older references to `main:app`, `/v3/authority/login`, `/dashboard/stats`, or generated one-off setup paths are historical and should not be used for new development.

## Runtime

- Python 3.10+
- FastAPI, Uvicorn, Pydantic v2
- Async SQLAlchemy
- SQLite by default, PostgreSQL-ready via `DATABASE_URL`
- Alembic migrations
- Optional Redis, MinIO/S3, Firebase, Twilio, and SOS webhook integrations

## Install

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Configure

Create `backend/.env` if needed. Development can run with defaults, but production must provide strong values.

Important settings:

```env
DATABASE_URL=sqlite+aiosqlite:///./saferoute.db
JWT_SECRET=replace-with-32-plus-byte-secret
DOC_NUMBER_SALT=replace-for-production
ALLOWED_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
MESH_SECRET_MASTER_KEY=replace-for-production
SOS_WORKER_ENABLED=true
SOS_DISPATCH_WEBHOOK_URL=
REDIS_URL=
MINIO_ENDPOINT=localhost:9000
MINIO_ACCESS_KEY=saferoute_access
MINIO_SECRET_KEY=saferoute_secret_change_me
MINIO_BUCKET=saferoute-media
```

RS256 QR signing uses either key files or base64 PEM environment variables. See `KEYS.md`.

## Database

```powershell
cd backend
alembic upgrade head
python seed_data.py
```

The app also calls `Base.metadata.create_all()` on startup for the local/hackathon SQLite path and performs a few idempotent SQLite compatibility column additions. Alembic remains the source of truth for committed schema changes.

## Run

```powershell
cd backend
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Useful URLs:

- `GET /health`
- `GET /live`
- `GET /ready`
- `GET /metrics`
- `GET /docs`

## Current Mounted Route Groups

| Prefix | Purpose |
| --- | --- |
| `/auth` | Authority registration/login and token refresh |
| `/v3/tourist` | Tourist registration, login, photo access, mesh-key rotation, QR refresh |
| `/v3/trips` | Trip create/list/active/end/cancel |
| `/v3/groups` | Tourist group create/join/active/members/sharing/leave |
| `/location` | Authenticated location pings |
| `/sos` | Direct SOS, BLE relay SOS, tourist status, authority events, audit, acknowledge, resolve |
| `/zones` | Active zones, destination zones, create/update/deactivate |
| `/destinations` | Destination catalogue, detail, trail graph placeholder, authority create/deactivate |
| `/dashboard` | Authority metrics, analytics, tourists, last locations |
| `/authority` | Authority device registration and QR/TUID scan |
| `/identity` | Public duplicate-check identity verification |
| `/v3/media` | Presigned upload URL and authenticated local download |
| `/rooms` | Room create/join/websocket |
| `/onboard` | Offline onboarding bundle and preview QR |
| `/.well-known` | QR public key |

See `../docs/api-contracts.md` for request and response summaries.

## SOS Worker

When `SOS_WORKER_ENABLED=true`, startup launches a background worker that:

- processes due `sos_dispatch_queue` rows,
- writes `sos_delivery_audit` rows,
- tries webhook, SMS, and FCM channels when configured,
- applies provider circuit state,
- escalates delivered-but-unacknowledged incidents,
- expires undelivered or unresponded incidents after configured TTLs.

Defaults:

- `SOS_RETRY_INTERVAL_SECONDS=30`
- `SOS_DELIVERY_TTL_SECONDS=7200`
- `SOS_ESCALATE_AFTER_SECONDS=1800`
- `SOS_EXPIRE_RESPONSE_AFTER_SECONDS=14400`

## Tests

```powershell
cd backend
python -m pytest tests -q
python -m pytest tests/test_sos_routes.py -q
python -m pytest tests/test_group_safety.py -q
```

The root `pytest.ini` also includes `mobile/test`; run backend tests from `backend/` when you want only Python tests.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `ModuleNotFoundError` | Activate the virtual environment and reinstall `requirements.txt`. |
| `RS256 keys missing` in production | Generate keys with `python generate_keys.py` or set base64 PEM env vars. |
| Dashboard CORS failure | Add the dashboard origin to `ALLOWED_ORIGINS`. |
| SOS remains queued | Configure webhook/Twilio/Firebase targets or inspect `/sos/events/{id}/delivery`. |
| MinIO unavailable | Local media upload URLs return `503`; local multipart registration still stores files under `uploaded_files/`. |
