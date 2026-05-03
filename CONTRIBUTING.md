# Contributing to SafeRoute

Welcome to SafeRoute! This guide covers everything you need to contribute effectively — from local setup to submitting your first pull request.

---

## 📁 Project Structure

```
SafeRoute/
├── mobile/          # Flutter app (Tourist + Authority modules)
│   └── lib/
│       ├── core/        # Shared: theme, errors, providers, repositories
│       ├── tourist/     # Tourist module (screens, providers, models)
│       ├── authority/   # Authority Hub (screens)
│       ├── services/    # All backend service calls
│       └── widgets/     # Shared UI components
├── backend/         # FastAPI Python backend
│   └── app/
│       ├── routes/      # API route handlers
│       ├── models/      # SQLAlchemy models
│       ├── services/    # Business logic
│       └── db/          # Database layer (SQLite + migrations)
└── dashboard/       # React + Vite admin dashboard
```

---

## 🛠️ Local Development Setup

### Prerequisites
- **Flutter**: 3.x+ (`flutter --version`)
- **Python**: 3.10+ (`python --version`)
- **Node.js**: 18+ (`node --version`)
- **Docker** (optional, recommended for backend DB)

### 1. Clone & Setup

```bash
git clone https://github.com/Abhishek01112002/SafeRoute.git
cd SafeRoute
```

### 2. Backend

```bash
cd backend
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS/Linux

pip install -r requirements.txt

# Copy environment file
cp .env.example .env
# Edit .env with your local values

# Run database migrations
alembic upgrade head

# Seed test data (optional)
python seed_data.py

# Start the backend
uvicorn app.main:app --reload --port 8000
```

Backend will be running at: `http://localhost:8000`  
Interactive API docs at: `http://localhost:8000/docs`

### 3. Mobile App

```bash
cd mobile
flutter pub get

# Run against local backend (default dev config)
flutter run -t lib/main_dev.dart

# Run against production backend
flutter run -t lib/main_prod.dart
```

### 4. Dashboard

```bash
cd dashboard
npm install
npm run dev
```

---

## 🌿 Branching Strategy

| Branch | Purpose |
|---|---|
| `main` | Production-ready code only |
| `develop` | Integration branch for features |
| `feature/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `chore/<name>` | Refactors, docs, config |

**Example**: `feature/tourist-group-safety`, `fix/sos-offline-crash`

```bash
# Always branch from develop:
git checkout develop
git pull origin develop
git checkout -b feature/my-feature
```

---

## 📐 Coding Standards

### Dart / Flutter
- **Imports**: Always use **absolute package imports** (`package:saferoute/...`), never relative (`../`)
- **Errors**: New code returns `Result<T>` — do not add new try/catch blocks in Providers
- **Assets**: Use `AppAssets.animations.xxx` — never hardcode `'assets/...'` strings
- **Colors**: Use `AppColors.primary`, `AppColors.danger` — never hardcode hex values
- **Spacing**: Use `AppSpacing.m`, `AppSpacing.l` — never hardcode pixel values
- **Run before PR**: `flutter analyze` must produce zero errors

### Python / FastAPI
- **Database changes**: Always use Alembic migrations — never raw `ALTER TABLE` or `CREATE TABLE`
- **Testing**: All new routes must have a pytest test covering: auth required, validation errors, happy path
- **Logging**: Use `structlog` or the existing `logging_config` — never use bare `print()`
- **Run before PR**: `pytest backend/tests/` must all pass

---

## 📝 Commit Message Format

```
<type>(<scope>): <short description>

Types: feat, fix, docs, chore, refactor, test, perf
Scope: mobile, backend, dashboard, core

Examples:
feat(mobile): add SOS offline queue with mesh relay
fix(backend): correct latitude validation range in /sos/trigger
docs(mobile): update CONTRIBUTING with Alembic setup
test(backend): add pytest coverage for /auth/refresh endpoint
```

---

## ✅ PR Checklist

Before opening a PR, ensure:

1. `flutter analyze` → zero errors
2. `flutter test` → all tests pass
3. `pytest backend/tests/` → all tests pass
4. No hardcoded strings (assets, colors, URLs)
5. Offline mode tested (airplane mode on device/emulator)
6. New database columns have an Alembic migration file
7. PR description filled using the PR template

---

## 🔍 Code Review Guidelines

- Reviews should be completed within **48 hours**
- Use the GitHub suggestion feature for small fixes
- Tag `@lead-dev` for architecture decisions
- One approval required to merge to `develop`
- Two approvals required to merge to `main`

---

## 🧪 Running Tests

```bash
# Mobile
cd mobile
flutter test                        # All tests
flutter test test/core/             # Core layer only
flutter test test/tourist/          # Tourist module only

# Backend
cd backend
pytest backend/tests/ -v            # All tests, verbose
pytest backend/tests/test_sos.py    # Specific file
pytest -k "test_sos_trigger"        # Specific test by name
```

---

## 🔑 Environment Variables

Never commit `.env` or secret keys. See `backend/.env.example` for required variables and `backend/KEYS.md` for key generation instructions.

---

## ❓ Getting Help

- Open a GitHub Discussion for questions
- Tag relevant owners (see `CODEOWNERS`)
- Check `docs/api-contracts.md` for API reference
