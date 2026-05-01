# 🛰️ SafeRoute: The Ultimate Comprehensive Technical Report
**Project Name**: SafeRoute (Uttarakhand Expedition Safety)  
**Status**: Beta v2.5 (65% Complete | Production-Ready Foundation)  
**Architecture**: Decoupled Hybrid Mesh (Flutter + FastAPI)

---

## 📂 1. Complete Project Folder Structure
```text
SafeRoute/
├── android/                                  # Android-specific native code, service bridges, permissions
│   ├── app/src/main/kotlin/com/saferoute/app/
│   │   ├── APIManager.kt                     # Native REST helper for app-level operations
│   │   ├── LocalDatabase.kt                  # Native SQLite helper layer
│   │   ├── LocationTracker.kt                # Android location listener wrapper
│   │   └── TrackingService.kt                # Background location service entrypoint
│   └── app/src/main/kotlin/com/example/saferoute/MainActivity.kt
├── assets/                                   # Static assets
│   ├── animations/                           # Lottie/Rive animations for SOS/Loading
│   └── trail_graph.json                      # Pre-computed offline trail graph & route geometry
├── backend/                                  # FastAPI Backend (Python)
│   ├── main.py                               # Core API logic, auth, WebSockets, persistence
│   ├── destinations_data.py                  # Destination metadata, connectivity, geo-fence rules
│   ├── requirements.txt                      # Python dependency pinning
│   └── saferoute.db                           # SQLite production datastore (runtime-created)
├── lib/                                      # Flutter Application Core
│   ├── main.dart                             # App entry + provider composition + startup orchestration
│   ├── mesh/                                 # BLE Mesh networking layer
│   │   ├── models/                            # Mesh packet and node schema
│   │   ├── providers/                         # Mesh state management and relay logic
│   │   ├── screens/                           # BLE status and debug UI
│   │   └── services/                          # BLE radio, advertising, and scanning logic
│   ├── models/                               # Data models (Tourist, Ping, Room, Geofence)
│   ├── providers/                            # Business logic and shared state
│   │   ├── auth_provider.dart                 # JWT auth state + secure token recovery
│   │   ├── location_provider.dart             # GPS smoothing, zone hysteresis, offline persistence
│   │   ├── mesh_provider.dart                 # Mesh lifecycle, SOS relay, nearby node feed
│   │   ├── safety_system_provider.dart        # risk events and alert orchestration
│   │   ├── tourist_provider.dart              # registration, sync and connectivity recovery
│   │   ├── room_provider.dart                 # group room join/create state
│   │   └── theme_provider.dart                # dark/light theme persistence
│   ├── screens/                              # UI screens
│   │   ├── home_screen_v2.dart                # Mission control dashboard
│   │   ├── navigation_screen_v2.dart          # Tactical navigation HUD
│   │   ├── sos_screen_v2.dart                 # 3-second SOS hold button
│   │   ├── tactical_ar_screen.dart            # Camera AR navigation overlay
│   │   ├── digital_id_screen.dart             # Tourist digital identity + offline mode state
│   │   ├── authority_dashboard_screen.dart    # Authority monitoring UI
│   │   ├── onboarding_screen.dart             # first-time registration flow
│   │   └── mesh_status_screen.dart            # BLE mesh status and SOS relay UI
│   ├── services/                             # Core infrastructure services
│   │   ├── api_service.dart                   # Dio REST client + JWT interceptor + offline fallback
│   │   ├── background_service.dart            # foreground isolate and background service startup
│   │   ├── database_service.dart              # SQLite CRUD and local cache management
│   │   ├── geofencing_engine.dart             # polygon & zone membership math
│   │   ├── pathfinding_service.dart           # offline A* trail graph navigator
│   │   ├── fall_detection_service.dart        # accelerometer fall heuristic
│   │   ├── location_service.dart              # raw GPS access and stream wrapper
│   │   ├── room_service.dart                  # API room creation/joining
│   │   ├── sync_service.dart                  # offline data sync when connectivity returns
│   │   ├── breadcrumb_manager.dart            # movement trail persistence
│   │   ├── notification_service.dart          # local notification registration
│   │   └── secure_storage_service.dart        # secure JWT and tourist ID storage
│   ├── utils/                                # Design tokens and helpers
│   │   ├── app_theme.dart                     # Aurora theme, color palette, glass tokens
│   │   ├── constants.dart                     # API base URL, timeouts, SOS hold duration
│   │   ├── date_formatter.dart                # human-friendly time labels
│   │   └── permission_helper.dart             # location/notification permission flow
│   └── widgets/                              # reusable UI components
│       ├── premium_components.dart            # buttons, cards, pulse markers, offline pack card
│       ├── premium_widgets.dart               # glassmorphism wrappers and animated indicators
│       ├── zone_status_card.dart              # dynamic danger/safe zone panel
│       └── connectivity_chip.dart             # online/offline status chip
├── test/                                     # Unit and widget test coverage
│   ├── mesh_test.dart                         # BLE mesh logic tests
│   └── widget_test.dart                       # Flutter widget smoke tests
└── pubspec.yaml                              # Flutter dependencies & project metadata
```

---

## 🚀 2. Strategic Approaches
- **Hybrid Connectivity**: Uses REST when 4G is available and a BLE fallback when cellular is absent. The mesh layer broadcasts SOS and location packets over nearby devices using `flutter_blue_plus` + peripheral advertising.
- **Offline-First**: Every location ping, SOS event, geo-fence geometry, and trail graph is available offline and persisted in SQLite via `lib/services/database_service.dart` and `lib/services/breadcrumb_manager.dart`.
- **Component-Driven UI**: The `AppTheme` system in `lib/utils/app_theme.dart` defines a locked Aurora palette, spacing, motion tokens, glassmorphism, and high-contrast zone colors.
- **Edge Intelligence**: Critical operations such as location smoothing, safety risk scoring, fall detection, and zone transition hysteresis run outside the main render path to preserve smooth UI updates.
- **Security by Design**: `ApiService` attaches JWT Bearer tokens from secure storage and fallback registration supports offline onboarding when backend access fails.

---

## ⚙️ 3. Backend Technical Logic (FastAPI)
The backend is a resilient FastAPI server with the following capabilities:
- **JWT Authentication**: `HS256` tokens generated in `backend/main.py` with 24-hour expiry.
- **Authority & Tourist Auth**: Separate registration/login flows for authorities and tourists using `bcrypt` password hashing.
- **Persistent Storage**: SQLite tables for `tourists`, `authorities`, and `sos_events` with JSON-encoded payloads for dynamic tourist data.
- **Geo-Decision Support**: `destinations_data.py` provides destination-level connectivity and risk metadata that the backend uses to derive offline mode requirements and geo-fence zones.
- **Real-Time Sharing**: WebSocket endpoint `/ws/{room_id}/{user_id}` performs token validation in query params and broadcasts room updates to active connections.
- **Safe Room Lifecycle**: REST endpoints for `/rooms/create`, `/rooms/{room_id}/join`, and live location sync.
- **Offline Recovery**: The backend supports tourist login, JWT refresh, location ping ingestion, and SOS persistence even if the app later goes back online.

### Backend endpoints
- `GET /health`
- `GET /destinations/states`
- `GET /destinations/{state}`
- `POST /auth/register/authority`
- `POST /auth/login/authority`
- `POST /tourist/register`
- `POST /tourist/login`
- `POST /auth/refresh`
- `POST /location/ping`
- `POST /sos/trigger`
- `POST /rooms/create`
- `POST /rooms/{room_id}/join`
- `WS /ws/{room_id}/{user_id}`

---

## 📱 4. Frontend Technical Details (Flutter)
### App startup and architecture
- `lib/main.dart` initializes notifications, secure shared preferences, background service, auth provider, and BLE mesh auto-start for registered tourists.
- `MultiProvider` composes app state for theme, navigation, auth, tourist data, location, room state, safety, and mesh.
- `ThemeProvider` uses a timeout-protected `SharedPreferences` load to avoid theme jank.
- The app chooses between `OnboardingScreen` and `MainScreen` based on registration state.

### Core service architecture
- `ApiService`: Singleton `Dio` client with request/response logging, JWT bearer injection, and rich error handling.
- `LocationProvider`: performs accuracy filtering, Kalman-lite smoothing, zone hysteresis, and persistence via `BreadcrumbManager`.
- `MeshProvider`: wraps `MeshService`, tracks nearby mesh nodes, handles SOS alerts, broadcasts location updates, and maintains recent activity.
- `SafetySystemProvider`: deduplicates alerts, orchestrates event-driven SOS triggers, and logs risk events for UI presentation.
- `PathfindingService`: pure Dart A* route planner that loads `assets/trail_graph.json` and computes safe routes to the nearest green zone.
- `FallDetectionService`: accelerometer-based impact detection using `sensors_plus` and a 15-second inactivity guard.

### UI capabilities
- `home_screen_v2.dart`: mission control dashboard with safety telemetry, zone status, and quick SOS access.
- `navigation_screen_v2.dart`: offline navigation HUD built around trail graph routing.
- `sos_screen_v2.dart`: visually engaging 3-second hold SOS trigger and fallback logic for backend + mesh relay.
- `tactical_ar_screen.dart`: camera overlay plus bearing arrows and heading smoothing for on-foot rescue guidance.
- `digital_id_screen.dart`: digital tourist identity with offline protection and secure data display.
- `mesh_status_screen.dart`: BLE status monitor, nearby nodes list, and emergency relay controls.

---

## 🧠 5. Core Algorithms & Logic
### 5.1 Offline A* trail navigator
- `lib/services/pathfinding_service.dart` loads the bundled trail graph asset and creates a bidirectional adjacency list.
- It snaps the user to the nearest trail node, finds the nearest safe zone node, and runs A* using a straight-line heuristic.
- Results include full path geometry, total distance, and estimated time at 4 km/h.
- If a node is already inside a green zone, the planner returns a no-movement safe state.

### 5.2 Zone-aware location processing
- `lib/providers/location_provider.dart` filters GPS points with accuracy > 20m.
- It applies a smoothing blend of 70% previous position and 30% raw update.
- Zone changes use 2-second hysteresis to avoid false positives from GPS jitter.
- Location saves only happen after spatial/time thresholds to reduce write load.

### 5.3 Mesh relay and SOS propagation
- `MeshProvider` sends `MeshPacketType.SOS_ALERT` and `LOCATION_UPDATE` packets.
- Incoming packets are stored in UI-visible `recentActivity` and reduced to the last 50 items.
- The service uses BLE advertising + scanning as a probabilistic flood relay, which is more robust than tightly coupled mesh routing in a hackathon context.

### 5.4 Fall detection heuristic
- Accelerometer magnitude is computed as `sqrt(x² + y² + z²)`.
- A spike threshold at **30 m/s²** triggers a 15-second inactivity watch.
- The provider treats this as a potential fall and can auto-activate SOS in the safety workflow.

---

## 🗃️ 6. Data Models & Persistence
### App persistence stack
- Flutter uses `sqflite`, `path_provider`, `shared_preferences`, and `flutter_secure_storage`.
- The app persists tourist profiles, geo-fence zones, offline pings, SOS events, and trail breadcrumbs locally.
- `lib/models/tourist_model.dart` supports JSON and SQLite serialization, including nested geo-fence zones.
- `ApiService` also supports offline registration fallback by generating a local offline tourist ID.

### Security storage
- JWT tokens are stored securely via `SecureStorageService`.
- Shared preferences store registration state and tourist ID.
- Native Android helpers in `android/app/src/main/kotlin/com/saferoute/app` support low-level tracking flows.

---

## 🧪 7. Dependency and Runtime Profile
### Key dependencies
- `provider` for state management
- `dio` for HTTP + JWT bearer interception
- `flutter_blue_plus` and `flutter_ble_peripheral` for BLE mesh
- `geolocator` + `permission_handler` for GPS and runtime permission handling
- `flutter_background_service` for persistent tracking
- `flutter_local_notifications` for local alerts
- `sensors_plus` for fall detection
- `flutter_map` + `latlong2` for map rendering
- `shared_preferences` + `flutter_secure_storage` for state persistence
- `sqflite` for offline SQLite storage

### Native runtime support
- Android native services and trackers are included to support background location and database operations on lower-level Android APIs.

---

## 📈 8. Validation & Test Summary
| Area | Source | Outcome |
| :--- | :--- | :--- |
| Mesh relay | UI debug / BLE status screen | Detected and relayed packets successfully in nearby device tests |
| Offline mode | Registration fallback path | Successful offline tourist creation when backend unreachable |
| SOS flow | `sos_screen_v2.dart` + backend `/sos/trigger` | Backend persisted SOS events and mesh relay queued UDP-like packets |
| Navigation | pathfinding_service A* | Safe route found using offline trail graph asset |
| UI performance | Flutter DevTools | 60 FPS stable through animated SOS interactions |

---

## 🔮 9. Future Scope & Roadmap
- **Mesh hardening**: Add hop count, duplicate packet suppression, and mesh mesh topology awareness.
- **Authority insights**: Add geofence breach alerts, live room telemetry, and officer dispatch.
- **Navigation 3.0**: Add slope-aware route scoring and voice-guided fallback navigation.
- **Hybrid comms**: Add satellite/mesh switchover and SMS/WhatsApp emergency ping gateways.
- **Rescue AR HUD**: Build a lightweight AR view for rescue teams with breadcrumb overlays.

---

## 💡 10. Feasibility & Viability Analysis
### 10.1 Technical feasibility
- **Device coverage**: Works on stock Android devices with BLE and GPS; no additional hardware required.
- **Offline resilience**: The app intentionally favors cached data and offline fallback over brittle network-only failures.
- **Security hygiene**: JWT, bcrypt, and secure storage protect identity and improve auditability.

### 10.2 Market fit
- **Low cost**: Minimal infrastructure required beyond mobile devices and a simple backend.
- **Government appeal**: Maps well to trekking safety mandates and digital permit systems.
- **Rescue utility**: Supports authority monitoring, SOS propagation, and offline route guidance.

---

## ✅ 11. Project Status Snapshot
- **Completion**: **65%**.
- **Stable subsystems**: Auth flow, theme system, location core, mesh service, backend persistence.
- **Work in progress**: Group safety UX, advanced offline navigation, multi-hop mesh, AR integration.
- **Highest priority next work**: strengthen offline mesh relay, tighten WebSocket room sync, and complete `navigation_screen_v2.dart` experience.

---

## 🏁 12. Strategic Summary
SafeRoute is purpose-built as a resilient, offline-first safety platform for rugged terrain. The current implementation balances strong UX, secure identity, BLE fallback communications, offline route planning, and authority integration.

> **Developer note**: Continue to extend the codebase from `lib/utils/app_theme.dart`, preserve the Aurora design system, and keep all safety-critical state in providers and services, not directly inside UI widgets.
