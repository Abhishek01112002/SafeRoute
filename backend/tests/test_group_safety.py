import asyncio
import datetime
import time

from app.db.session import AsyncSessionLocal
from app.models.database import Tourist, TouristGroup, TouristGroupLocationSnapshot
from app.services.jwt_service import create_jwt_token


def _run_async(coro):
    return asyncio.run(coro)


async def _seed_tourist(tourist_id: str, full_name: str) -> None:
    async with AsyncSessionLocal() as db:
        async with db.begin():
            existing = await db.get(Tourist, tourist_id)
            if existing:
                return
            now = datetime.datetime.now()
            db.add(
                Tourist(
                    tourist_id=tourist_id,
                    tuid=f"TUID-{tourist_id[-8:]}",
                    document_number_hash=f"hash-{tourist_id}",
                    date_of_birth="1990-01-01",
                    nationality="IN",
                    full_name=full_name,
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


def _auth(tourist_id: str) -> dict:
    token = create_jwt_token(tourist_id, role="tourist")
    return {"Authorization": f"Bearer {token}"}


def test_group_create_join_pause_leave_and_active_restore(client):
    owner = "TID-GROUP-OWNER-001"
    member = "TID-GROUP-MEMBER-001"
    _run_async(_seed_tourist(owner, "Owner Tourist"))
    _run_async(_seed_tourist(member, "Member Tourist"))

    created = client.post(
        "/v3/groups",
        json={"name": "Kedarnath Team", "destination_id": "UK_KED_001"},
        headers=_auth(owner),
    )
    assert created.status_code == 200, created.text
    group = created.json()
    assert len(group["invite_code"]) == 6
    assert group["members"][0]["tourist_id"] == owner

    joined = client.post(f"/v3/groups/{group['invite_code']}/join", headers=_auth(member))
    assert joined.status_code == 200, joined.text
    assert {m["tourist_id"] for m in joined.json()["members"]} == {owner, member}

    paused = client.post(
        f"/v3/groups/{group['group_id']}/sharing",
        json={"sharing": False},
        headers=_auth(member),
    )
    assert paused.status_code == 200, paused.text
    paused_member = next(m for m in paused.json()["members"] if m["tourist_id"] == member)
    assert paused_member["sharing_status"] == "PAUSED"

    active = client.get("/v3/groups/active", headers=_auth(member))
    assert active.status_code == 200, active.text
    assert active.json()["active_group"]["group_id"] == group["group_id"]

    left = client.post(f"/v3/groups/{group['group_id']}/leave", headers=_auth(member))
    assert left.status_code == 200, left.text
    assert left.json()["status"] == "left"

    active_after_leave = client.get("/v3/groups/active", headers=_auth(member))
    assert active_after_leave.status_code == 200
    assert active_after_leave.json()["active_group"] is None


def test_rooms_wrapper_uses_persistent_group_state(client):
    owner = "TID-GROUP-OWNER-002"
    member = "TID-GROUP-MEMBER-002"
    _run_async(_seed_tourist(owner, "Wrapper Owner"))
    _run_async(_seed_tourist(member, "Wrapper Member"))

    created = client.post("/rooms/create", json={}, headers=_auth(owner))
    assert created.status_code == 200, created.text
    room = created.json()

    joined = client.post(f"/rooms/{room['room_id']}/join", headers=_auth(member))
    assert joined.status_code == 200, joined.text
    assert joined.json()["group_id"] == room["group_id"]

    active = client.get("/v3/groups/active", headers=_auth(member))
    assert active.status_code == 200, active.text
    assert active.json()["active_group"]["group_id"] == room["group_id"]


def test_joining_second_group_reports_active_group_conflict(client):
    owner_one = "TID-GROUP-OWNER-006"
    owner_two = "TID-GROUP-OWNER-007"
    member = "TID-GROUP-MEMBER-006"
    _run_async(_seed_tourist(owner_one, "First Owner"))
    _run_async(_seed_tourist(owner_two, "Second Owner"))
    _run_async(_seed_tourist(member, "Busy Member"))

    first = client.post("/v3/groups", json={"name": "First Team"}, headers=_auth(owner_one))
    second = client.post("/v3/groups", json={"name": "Second Team"}, headers=_auth(owner_two))
    assert first.status_code == 200, first.text
    assert second.status_code == 200, second.text

    joined = client.post(f"/v3/groups/{first.json()['invite_code']}/join", headers=_auth(member))
    assert joined.status_code == 200, joined.text

    conflict = client.post(f"/v3/groups/{second.json()['invite_code']}/join", headers=_auth(member))
    assert conflict.status_code == 409, conflict.text
    detail = conflict.json()["detail"]
    assert detail["error"] == "Tourist already has an active group"
    assert detail["active_group_id"] == first.json()["group_id"]
    assert detail["active_invite_code"] == first.json()["invite_code"]


def test_room_websocket_expands_payload_and_upserts_latest_snapshot(client):
    owner = "TID-GROUP-OWNER-003"
    _run_async(_seed_tourist(owner, "Socket Owner"))
    token = create_jwt_token(owner, role="tourist")

    created = client.post("/rooms/create", json={}, headers=_auth(owner))
    assert created.status_code == 200, created.text
    room_id = created.json()["room_id"]
    group_id = created.json()["group_id"]

    with client.websocket_connect(f"/rooms/ws/{room_id}/{owner}?token={token}") as websocket:
        initial = websocket.receive_json()
        assert initial["type"] == "location_update"
        assert initial["group_id"] == group_id

        websocket.send_json(
            {
                "name": "Socket Owner",
                "lat": 30.742,
                "lng": 79.068,
                "timestamp": time.time(),
                "accuracy_meters": 7,
                "battery_level": 0.84,
                "zone_status": "SAFE",
            }
        )
        update = websocket.receive_json()
        assert update["type"] == "location_update", update
        me = next(m for m in update["members"] if m["tourist_id"] == owner)
        assert me["lat"] == 30.742
        assert me["accuracy_meters"] == 7
        assert me["battery_level"] == 0.84
        assert me["zone_status"] == "SAFE"
        assert me["source"] == "websocket"
        assert me["trust_level"] == "confirmed"

        websocket.send_json(
            {
                "lat": 30.743,
                "lng": 79.069,
                "timestamp": time.time(),
            }
        )
        limited = websocket.receive_json()
        assert limited["type"] == "rate_limited"

    async def snapshot_count() -> int:
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                TouristGroupLocationSnapshot.__table__.select().where(
                    TouristGroupLocationSnapshot.group_id == group_id,
                    TouristGroupLocationSnapshot.tourist_id == owner,
                )
            )
            return len(result.fetchall())

    assert _run_async(snapshot_count()) == 1


def test_group_sos_context_and_duplicate_throttle(client):
    owner = "TID-GROUP-OWNER-004"
    _run_async(_seed_tourist(owner, "SOS Owner"))

    created = client.post("/v3/groups", json={"name": "SOS Team"}, headers=_auth(owner))
    assert created.status_code == 200, created.text
    group_id = created.json()["group_id"]

    payload = {
        "latitude": 30.742,
        "longitude": 79.068,
        "trigger_type": "MANUAL",
        "timestamp": datetime.datetime.now().isoformat(),
        "group_id": group_id,
    }
    first = client.post("/sos/trigger", json=payload, headers=_auth(owner))
    assert first.status_code == 202, first.text
    assert first.json()["group_id"] == group_id

    second = client.post("/sos/trigger", json=payload, headers=_auth(owner))
    assert second.status_code == 202, second.text
    assert second.json()["status"] == "duplicate_group_sos_ignored"


def test_expired_invite_counts_failed_join_attempts(client):
    owner = "TID-GROUP-OWNER-005"
    member = "TID-GROUP-MEMBER-005"
    _run_async(_seed_tourist(owner, "Expiry Owner"))
    _run_async(_seed_tourist(member, "Expiry Member"))

    created = client.post("/v3/groups", json={"name": "Expired Invite"}, headers=_auth(owner))
    assert created.status_code == 200, created.text
    invite_code = created.json()["invite_code"]
    group_id = created.json()["group_id"]

    async def expire_invite() -> None:
        async with AsyncSessionLocal() as db:
            async with db.begin():
                group = await db.get(TouristGroup, group_id)
                group.invite_expires_at = (
                    datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None)
                    - datetime.timedelta(minutes=1)
                )

    _run_async(expire_invite())

    for _ in range(5):
        response = client.post(f"/v3/groups/{invite_code}/join", headers=_auth(member))
        assert response.status_code == 404, response.text

    locked = client.post(f"/v3/groups/{invite_code}/join", headers=_auth(member))
    assert locked.status_code == 429, locked.text
