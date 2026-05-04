# backend/tests/conftest.py
#
# Shared pytest fixtures for all SafeRoute backend tests.
# Provides: test client, auth tokens, seeded test tourist/authority.
# Import into any test file: fixtures are auto-discovered by pytest.

import pytest
import datetime
import os
import sys

# Ensure app can be imported when running from backend/ directory
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Disable external dependencies for tests
os.environ["REDIS_URL"] = ""

from fastapi.testclient import TestClient
from app import create_app
from app.services.jwt_service import create_jwt_token
from app.db import sqlite_legacy
from app.core import limiter

# Disable rate limiter for tests to prevent 429 Too Many Requests
limiter.enabled = False

# ---------------------------------------------------------------------------
# Test data constants
# ---------------------------------------------------------------------------

TEST_TOURIST_ID = "TID-2025-UK-TEST1"
TEST_TOURIST_TUID = "TUID-CONFTEST-TOURIST-0001"
TEST_AUTHORITY_ID = "AUTH-2025-TEST-001"

# ---------------------------------------------------------------------------
# App + Client
# ---------------------------------------------------------------------------

@pytest.fixture(scope="session")
def app():
    """Create the FastAPI app once per test session."""
    return create_app()


@pytest.fixture(scope="session")
def client(app):
    """HTTP test client for the full FastAPI app.

    NOTE: TestClient with scope='session' does NOT trigger FastAPI's
    @app.on_event('startup'). We therefore call init_models() manually
    so that SQLAlchemy ORM tables (sos_events, location_pings, …) exist
    before any test hits the database.
    """
    import asyncio
    from app.db.session import init_models
    from app.db.sqlite_legacy import init_db, sync_from_db

    asyncio.get_event_loop().run_until_complete(init_models())
    init_db()
    sync_from_db()

    return TestClient(app)


# ---------------------------------------------------------------------------
# Database setup
# ---------------------------------------------------------------------------

@pytest.fixture(autouse=True)
def seed_test_tourist():
    """
    Seeds a known tourist into the SQLite in-memory DB before each test.
    Automatically runs for all tests (autouse=True).
    Cleans up after test completes.
    """
    sqlite_legacy.init_db()

    tourist_data = {
        "tourist_id": TEST_TOURIST_ID,
        "tuid": TEST_TOURIST_TUID,
        "full_name": "Test Tourist Conftest",
        "nationality": "IN",
        "document_type": "AADHAAR",
        "document_number": "0000-0000-0000",
        "emergency_contact_name": "Test Contact",
        "emergency_contact_phone": "+91-9999999999",
        "trip_start_date": datetime.datetime.now().isoformat(),
        "trip_end_date": (datetime.datetime.now() + datetime.timedelta(days=7)).isoformat(),
        "destination_state": "Uttarakhand",
        "selected_destinations": [],
        "blood_group": "O+",
        "qr_data": f"QR-{TEST_TOURIST_ID}",
    }

    sqlite_legacy.save_tourist(TEST_TOURIST_ID, tourist_data)
    sqlite_legacy.tourists_db[TEST_TOURIST_ID] = tourist_data

    yield

    # Cleanup: remove test tourist from in-memory store
    sqlite_legacy.tourists_db.pop(TEST_TOURIST_ID, None)


# ---------------------------------------------------------------------------
# Auth headers
# ---------------------------------------------------------------------------

@pytest.fixture
def tourist_auth_header():
    """Bearer token header for the test tourist."""
    token = create_jwt_token(TEST_TOURIST_ID, role="tourist")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def authority_auth_header():
    """Bearer token header for a test authority user."""
    token = create_jwt_token(TEST_AUTHORITY_ID, role="authority")
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def expired_token_header():
    """Auth header with an already-expired JWT (for testing 401 cases)."""
    token = create_jwt_token(
        TEST_TOURIST_ID,
        role="tourist",
        expires_delta=datetime.timedelta(seconds=-10),  # already expired
    )
    return {"Authorization": f"Bearer {token}"}


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def valid_sos_payload():
    """Returns a valid SOS trigger payload with a current timestamp."""
    return {
        "latitude": 30.7333,
        "longitude": 79.0667,
        "trigger_type": "MANUAL",
        "timestamp": datetime.datetime.now().isoformat(),
    }


def valid_location_payload():
    """Returns a valid location ping payload."""
    return {
        "tourist_id": TEST_TOURIST_ID,
        "latitude": 30.7333,
        "longitude": 79.0667,
        "speed_kmh": 12.5,
        "accuracy_meters": 5.0,
        "zone_status": "SAFE",
        "timestamp": datetime.datetime.now().isoformat(),
    }
