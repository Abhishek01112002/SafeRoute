# SafeRoute Mobile

Last reviewed: 2026-05-16

The mobile app is the tourist-facing SafeRoute client with supporting authority screens. It uses Flutter, Provider state management, SQLite-backed local services, BLE mesh relay, maps, Firebase telemetry, and background services.

Current default debug URLs in `lib/main.dart` are `http://10.43.205.74:8000` and `ws://10.43.205.74:8000`. These are machine-specific development defaults, so most developers should pass `SAFEROUTE_API_BASE_URL` and `SAFEROUTE_WS_URL` explicitly.

## Current Entry Points

| File | Purpose |
| --- | --- |
| `lib/main.dart` | Default entry point. Debug uses development API/WebSocket defaults; release points at the deployed staging backend unless overridden. |
| `lib/main_dev.dart` | Dev flavor entry point. |
| `lib/main_staging.dart` | Staging flavor entry point. |
| `lib/main_prod.dart` | Production flavor entry point. |
| `lib/bootstrap.dart` | Shared app initialization, providers, Firebase/Crashlytics setup, notifications, local cleanup, background service setup. |

## Run

```powershell
cd mobile
flutter pub get
flutter run --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000 --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000
```

Android flavor commands:

```powershell
flutter run --flavor dev -t lib/main_dev.dart
flutter run --flavor staging -t lib/main_staging.dart --release
flutter build appbundle --flavor prod -t lib/main_prod.dart
```

App IDs:

- Dev: `com.saferoute.app.dev`
- Staging: `com.saferoute.app.staging`
- Prod: `com.saferoute.app`

## Backend URL Overrides

Most local device testing needs your machine LAN IP:

```powershell
flutter run --flavor dev -t lib/main_dev.dart --dart-define=SAFEROUTE_API_BASE_URL=http://<LAN_IP>:8000 --dart-define=SAFEROUTE_WS_URL=ws://<LAN_IP>:8000
```

TLS pinning can be configured with:

```text
--dart-define=SAFEROUTE_TLS_CERT_SHA256=<hex-sha256>
```

## Current Tourist Experience

- Onboarding and permission setup.
- Tourist registration and login against the backend.
- Digital ID / QR display.
- Start-trip and active-trip flows.
- Home, navigation, offline navigation, tactical AR, and map views.
- Zone status cards and geofencing safety updates.
- Group safety and room/WebSocket state.
- Mesh status screen and BLE relay support.
- SOS screen with hold-to-trigger behavior.
- Local database, tile cache, breadcrumb cleanup, sync engine, and background services.

## Important Services

| Service | Purpose |
| --- | --- |
| `ApiService` | Backend API client and auth/error handling. |
| `SyncEngine` | Offline-first synchronization. |
| `DatabaseService` | Local SQLite persistence and cleanup. |
| `MeshService` | BLE mesh packet behavior. |
| `SafetyEngine` | Risk-level computation from zone, battery, movement, and SOS state. |
| `GeofencingEngine` | Zone containment checks. |
| `PathfindingService` | Offline path calculations. |
| `BackgroundService` | Background tasks. |
| `TelemetryService` | Crash/error telemetry bridge. |

## Tests

```powershell
cd mobile
flutter analyze
flutter test
flutter test test/tourist
flutter test test/core
```

## Notes

- Registration is intentionally online-only so unverified ghost identities are not created.
- SOS, pings, navigation, tiles, and mesh behavior are designed to degrade gracefully when connectivity is poor.
- Tokens and mesh secrets should live in secure storage, not shared preferences.
