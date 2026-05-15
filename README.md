# SafeRoute

Last reviewed: 2026-05-16

SafeRoute is a tourist safety and emergency response platform for remote, high-altitude, and low-connectivity travel. The project is a monorepo with a FastAPI backend, a Flutter mobile app, and a React/Vite authority dashboard.

The current implementation centers on verified tourist identity, trip planning, location awareness, geofence safety zones, group safety, BLE SOS relay, and a queued multi-channel SOS delivery workflow for authorities.

## Current Architecture

| Area | Stack | Current role |
| --- | --- | --- |
| `backend/` | SafeRoute API v3.1.0 on FastAPI, async SQLAlchemy, Alembic, SQLite by default, PostgreSQL-ready | Canonical API for identity, auth, trips, groups, zones, SOS queueing, dashboard analytics, health checks, and storage hooks |
| `mobile/` | Flutter 3 / Dart 3, Provider, SQLite, BLE, maps, Firebase telemetry | Tourist app with registration, digital ID, trip start, navigation, geofencing, mesh status, group safety, SOS, background sync, and local caches |
| `dashboard/` | React 19, Vite, TypeScript, Leaflet, Axios, lucide-react | Authority command center for overview metrics, map operations, zone management, offline onboarding QR generation, and SOS triage |

## Implemented Highlights

- Tourist registration and login issue access and refresh JWTs, TUID identity data, QR payloads, and versioned mesh secrets.
- Authority registration and login use password strength checks, JWT auth, account status checks, and dashboard permissions.
- Trips are separated from tourist identity through `/v3/trips`, with one active trip at a time and multi-stop itinerary support.
- SOS events are queued with idempotency, delivery audit rows, provider circuit state, acknowledgement, resolution, escalation, and BLE relay support.
- BLE relay packets are verified with TUID suffixes, key versions, HMAC signatures, timestamp freshness, and idempotency hashes.
- Location pings store coordinates, speed, accuracy, zone status, TUID, and client timestamp.
- Dashboard analytics aggregate tourists, locations, active/resolved SOS events, trip states, freshness, and recent activity.
- Zones support circle and polygon shapes for `SAFE`, `CAUTION`, and `RESTRICTED` areas.
- Media and QR flows support RS256 QR signing, public-key publication, local file access checks, and optional MinIO presigned uploads.

## Quick Start

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
alembic upgrade head
python seed_data.py
python -m uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

Useful backend URLs:

- API: `http://localhost:8000`
- Swagger: `http://localhost:8000/docs`
- Health: `http://localhost:8000/health`
- Readiness: `http://localhost:8000/ready`
- Metrics: `http://localhost:8000/metrics`

### Dashboard

```powershell
cd dashboard
npm install
npm run dev
```

Set `VITE_API_BASE_URL=http://localhost:8000` when the dashboard should point at a non-default backend. The dashboard runs at `http://localhost:5173` by default.

### Mobile

```powershell
cd mobile
flutter pub get
flutter run --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000 --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000
```

Flavor entry points are also available:

```powershell
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart --release
flutter build appbundle --flavor prod -t lib/main_prod.dart
```

## Key Configuration

Backend settings are loaded from environment variables in `backend/app/config.py`. Important values include:

- `DATABASE_URL`
- `ENABLE_PG`, `ENABLE_DUAL_WRITE`, `READ_FROM_PG`
- `JWT_SECRET`
- `DOC_NUMBER_SALT`
- `ALLOWED_ORIGINS`
- `PRIVATE_KEY_PATH`, `PUBLIC_KEY_PATH`, or base64 equivalents
- `REDIS_URL`
- `MINIO_ENDPOINT`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`, `MINIO_BUCKET`
- `SOS_DISPATCH_WEBHOOK_URL`
- `SOS_WORKER_ENABLED`
- `MESH_SECRET_MASTER_KEY`

Production mode validates explicit CORS origins, strong JWT configuration, RS256 keys, and mesh secret configuration.

## Documentation Map

- API contracts: `docs/api-contracts.md`
- Monitoring: `docs/monitoring.md`
- BLE packet format: `docs/ble_packet_spec.md`
- Mesh secret lifecycle: `docs/mesh_secret_spec.md`
- Backend quick start: `backend/QUICK_START_GUIDE.md`
- Mobile details: `mobile/README.md`
- Dashboard details: `dashboard/README.md`
- Historical reports and older QA writeups: `docs/internal/`

## Validation

Common checks:

```powershell
cd backend
python -m pytest tests -q

cd ..\dashboard
npm run build

cd ..\mobile
flutter analyze
flutter test
```

The documentation was refreshed from the live codebase on 2026-05-16. Some historical reports remain for traceability and are marked with current-status notes.
