import asyncio
import datetime

from sqlalchemy import delete

from app.db import sqlite_legacy
from app.db.session import AsyncSessionLocal
from app.models.database import Destination, Tourist
from tests.conftest import TEST_TOURIST_ID, TEST_TOURIST_TUID, valid_location_payload, valid_sos_payload


def _run_async(coro):
    return asyncio.run(coro)


async def _seed_db_tourist(tourist_id: str = TEST_TOURIST_ID) -> None:
    async with AsyncSessionLocal() as db:
        async with db.begin():
            existing = await db.get(Tourist, tourist_id)
            if existing:
                return
            now = datetime.datetime.now()
            db.add(
                Tourist(
                    tourist_id=tourist_id,
                    tuid=TEST_TOURIST_TUID,
                    document_number_hash=f"test-hash-{tourist_id}",
                    date_of_birth="1990-01-01",
                    nationality="IN",
                    full_name="Dashboard Test Tourist",
                    document_type="AADHAAR",
                    emergency_contact_name="Emergency Contact",
                    emergency_contact_phone="+919999999999",
                    trip_start_date=now,
                    trip_end_date=now + datetime.timedelta(days=7),
                    destination_state="Uttarakhand",
                    qr_data=f"QR-{tourist_id}",
                    connectivity_level="GOOD",
                    offline_mode_required=False,
                    risk_level="LOW",
                    blood_group="O+",
                )
            )


async def _clear_db_destinations() -> None:
    async with AsyncSessionLocal() as db:
        async with db.begin():
            await db.execute(delete(Destination))


def test_dashboard_analytics_returns_command_centre_shape(client, authority_auth_header):
    _run_async(_seed_db_tourist())

    response = client.get("/dashboard/analytics", headers=authority_auth_header)

    assert response.status_code == 200, response.text
    body = response.json()
    assert "generated_at" in body
    assert "metrics" in body
    assert "freshness" in body
    assert "zone_breakdown" in body
    assert "sos_breakdown" in body
    assert "recent_activity" in body
    assert "registered_tourists" in body["metrics"]
    assert "active_trips" in body["metrics"]
    assert body["freshness"]["stale_threshold_minutes"] == 15


def test_destinations_fall_back_to_project_catalogue_when_db_is_empty(client):
    _run_async(_clear_db_destinations())

    response = client.get("/destinations")

    assert response.status_code == 200, response.text
    body = response.json()
    assert any(destination["id"] == "UK_KED_001" for destination in body)
    assert all(destination["center_lat"] is not None for destination in body)

    states = client.get("/destinations/states")
    assert states.status_code == 200, states.text
    assert "Uttarakhand" in states.json()

    detail = client.get("/destinations/UK_KED_001/detail")
    assert detail.status_code == 200, detail.text
    assert detail.json()["name"] == "Kedarnath Temple"


def test_dashboard_locations_are_db_backed_after_legacy_memory_clear(
    client, tourist_auth_header, authority_auth_header
):
    _run_async(_seed_db_tourist())

    first = valid_location_payload()
    first["timestamp"] = datetime.datetime.now().isoformat()
    first["zone_status"] = "SAFE"
    assert client.post("/location/ping", json=first, headers=tourist_auth_header).status_code == 200

    second = valid_location_payload()
    second["timestamp"] = (datetime.datetime.now() + datetime.timedelta(seconds=1)).isoformat()
    second["zone_status"] = "RESTRICTED"
    assert client.post("/location/ping", json=second, headers=tourist_auth_header).status_code == 200

    sqlite_legacy.location_logs.clear()

    response = client.get("/dashboard/locations?limit=20&offset=0", headers=authority_auth_header)

    assert response.status_code == 200, response.text
    rows = response.json()
    latest = next(row for row in rows if row["tourist_id"] == TEST_TOURIST_ID)
    assert latest["zone_status"] == "RESTRICTED"
    assert latest["tuid"] == TEST_TOURIST_TUID


def test_sos_respond_accepts_dashboard_response_payload(
    client, tourist_auth_header, authority_auth_header
):
    _run_async(_seed_db_tourist())

    trigger = client.post("/sos/trigger", json=valid_sos_payload(), headers=tourist_auth_header)
    assert trigger.status_code == 202, trigger.text

    events = client.get("/sos/events?limit=1&offset=0", headers=authority_auth_header)
    assert events.status_code == 200, events.text
    event_id = events.json()[0]["id"]

    response = client.post(
        f"/sos/events/{event_id}/respond",
        json={"response": "Response initiated from command centre"},
        headers=authority_auth_header,
    )

    assert response.status_code == 200, response.text
    assert response.json()["status"] == "resolved"
