# Makefile for SafeRoute
# Run any target with: make <target>
# Example: make dev, make test-backend, make lint

.PHONY: dev stop test-backend test-mobile lint-backend lint-mobile seed clean help

## ─────────────────────────────────────────────
## 🚀 Local Development
## ─────────────────────────────────────────────

dev: ## Start backend + DB with Docker Compose
	@echo "🚀 Starting SafeRoute backend..."
	docker compose -f backend/docker-compose.yml up -d
	@echo "✅ Backend running at http://localhost:8000"
	@echo "📖 API docs at http://localhost:8000/docs"

stop: ## Stop all Docker services
	docker compose -f backend/docker-compose.yml down

restart: ## Restart all Docker services
	docker compose -f backend/docker-compose.yml restart

logs: ## Follow backend logs
	docker compose -f backend/docker-compose.yml logs -f

## ─────────────────────────────────────────────
## 🧪 Testing
## ─────────────────────────────────────────────

test-backend: ## Run all backend pytest tests
	@echo "🐍 Running backend tests..."
	cd backend && python -m pytest tests/ -v --tb=short

test-mobile: ## Run all Flutter tests
	@echo "📱 Running Flutter tests..."
	cd mobile && flutter test

test: test-backend test-mobile ## Run all tests (backend + mobile)

test-backend-cov: ## Run backend tests with coverage report
	cd backend && python -m pytest tests/ -v --cov=app --cov-report=html
	@echo "Coverage report: backend/htmlcov/index.html"

## ─────────────────────────────────────────────
## 🔍 Linting & Analysis
## ─────────────────────────────────────────────

lint-backend: ## Run flake8 + isort check on backend
	cd backend && python -m flake8 app/ --max-line-length=120 --ignore=E501,W503
	@echo "✅ Backend lint passed"

lint-mobile: ## Run flutter analyze on mobile
	cd mobile && flutter analyze --no-fatal-infos
	@echo "✅ Mobile analyze passed"

lint: lint-backend lint-mobile ## Lint all layers

## ─────────────────────────────────────────────
## 🗄️ Database
## ─────────────────────────────────────────────

migrate: ## Apply all pending Alembic migrations
	@echo "🗄️ Running database migrations..."
	cd backend && alembic upgrade head
	@echo "✅ Migrations applied"

migration: ## Create a new Alembic migration (usage: make migration MSG="add column")
	cd backend && alembic revision --autogenerate -m "$(MSG)"

seed: ## Seed the database with development test data
	@echo "🌱 Seeding database..."
	cd backend && python seed_data.py
	@echo "✅ Database seeded"

db-reset: ## Drop and recreate the database (DANGER: dev only)
	@echo "⚠️  Resetting database (dev only)..."
	cd backend && alembic downgrade base && alembic upgrade head
	$(MAKE) seed

## ─────────────────────────────────────────────
## 📱 Mobile
## ─────────────────────────────────────────────

mobile-dev: ## Run mobile app against local dev backend
	cd mobile && flutter run -t lib/main_dev.dart

mobile-prod: ## Run mobile app against production backend
	cd mobile && flutter run -t lib/main_prod.dart

mobile-deps: ## Get Flutter dependencies
	cd mobile && flutter pub get

## ─────────────────────────────────────────────
## 🧹 Cleanup
## ─────────────────────────────────────────────

clean: ## Clean all build artifacts
	cd mobile && flutter clean
	cd mobile && flutter pub get
	@echo "✅ Cleaned mobile build artifacts"

clean-db: ## Remove local SQLite database files (dev only)
	find backend -name "*.db" -not -name ".gitkeep" -delete
	@echo "✅ Local databases removed"

## ─────────────────────────────────────────────
## ℹ️ Help
## ─────────────────────────────────────────────

help: ## Show this help message
	@echo "SafeRoute Development Commands"
	@echo "─────────────────────────────"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
