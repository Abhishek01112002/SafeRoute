# SafeRoute 🛡️

**SafeRoute** is a comprehensive, end-to-end safety and navigation ecosystem engineered for tourists navigating remote, high-altitude, or low-connectivity environments (specifically optimized for North East India).

SafeRoute combines real-time geofencing, offline-capable pathfinding, and instant distress signaling into a robust platform using BLE Mesh and GPS.

---

## 🏗️ Architecture overview

SafeRoute is structured as a monorepo containing three distinct, collaborative pillars:

- **`backend/`** — A high-performance Python **FastAPI** server powered by SQLite/PostgreSQL. It manages the canonical source of truth for all destinations, zones, and SOS events.
- **`mobile/`** — The **Flutter** mobile application for tourists. Designed with an offline-first methodology, relying on heavy local SQLite caching and BLE Mesh for continuous safety monitoring.
- **`dashboard/`** — A **React + Vite** web command center featuring a premium "Dark Punk" aesthetic. Used by Zone Authorities to monitor active tourists, dispatch SOS responses, and draw active geofence boundaries.

---

## ✨ Key Features

### 📱 Tourist Mobile App (Flutter)
*   **Offline-First Pathfinding:** Uses A* algorithms on pre-downloaded GeoJSON trail graphs to navigate tourists to safety, even with zero network connectivity.
*   **Dynamic Geofencing:** Syncs `SAFE`, `CAUTION`, and `RESTRICTED` boundaries from the backend. The app uses complex ray-casting to determine user status and triggers tactical haptic feedback upon entering dangerous areas.
*   **Intelligent Safety Engine:** Continuously calculates a "Safety Risk Level" based on current zone status, battery depletion rate, velocity (stillness detection), and mesh network availability.
*   **Automated SOS Dispatch:** One-tap SOS triggering. If connectivity is lost, the system relies on fallback mechanisms (like Bluetooth mesh pinging) to relay the distress signal.

### 💻 Authority Command Center (React)
*   **Real-Time SOS Monitoring:** A live tracker that segments active distress signals from resolved logs, allowing authorities to initiate rapid responses.
*   **Zone Manager:** A dynamic interface allowing authorities to deploy or retract geofence boundaries (circles and polygons) across their jurisdiction instantly.
*   **Premium Aesthetic:** Built with a cohesive "Dark Punk" UI—featuring neon accents, glassmorphism panels, and glitch hover animations—making the dashboard feel like a true tactical command center.

### ⚙️ Backend Infrastructure (FastAPI)
*   **Role-Based Access Control (RBAC):** Strict JWT-based authentication distinguishing between generic `tourist` tokens and heavily restricted `authority` tokens limited to specific district jurisdictions.
*   **Multi-Channel Alerts:** When a critical SOS is fired, the backend dispatches Firebase Cloud Messaging (FCM) push notifications, alongside SMS fallbacks (via Twilio) to the relevant authorities.

---

## 🚀 Getting Started

### Prerequisites
- Python 3.10+
- Flutter SDK 3.x
- Node.js 18+

### 1. Booting the Backend
```bash
cd backend
# 1. Copy environment variables
cp .env.example .env
# Add your JWT_SECRET, Twilio, and Firebase keys to .env

# 2. Install dependencies
pip install -r requirements.txt

# 3. Seed the database with initial destinations and zones
python manage.py seed

# 4. Create an admin account for the web dashboard
python manage.py create-authority

# 5. Run the server
uvicorn main:app --reload
```

### 2. Launching the Web Dashboard
```bash
cd dashboard
npm install
npm run dev
# The dashboard will be available at http://localhost:5173
```

### 3. Running the Mobile App
For production or registration-enabled builds, you **must** provide a cryptographic salt for TUID generation.

```bash
cd mobile
flutter pub get

# Development run (uses default salt)
flutter run

# Production-ready run with custom salt
flutter run --dart-define=SAFEROUTE_TUID_SALT="your_secure_random_salt_here"
```

---

## 🔒 Security & Privacy

### Secret Management
SafeRoute uses a multi-layered security approach:
- **Environment Injection:** Sensitive keys (Twilio, Firebase, Salts) are injected via `.env` files (backend) or `--dart-define` (mobile).
- **Pre-commit Hooks:** The repository includes `detect-secrets` to prevent accidental commits of API keys.
- **GitHub Actions:** Automated `gitleaks` scanning runs on every push to catch any leaked credentials.

To initialize local secret detection:
```bash
pip install pre-commit
pre-commit install
```

### Data Retention
To prioritize user privacy and optimize storage, location breadcrumbs are automatically pruned from the local device after **72 hours**. Location data is only dispatched to the centralized server during explicit SOS events or while navigating active `RESTRICTED` zones.
