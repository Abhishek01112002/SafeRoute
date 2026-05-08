"""
backend/seed_data.py
One-time idempotent seed — migrates the old hardcoded destinations_data.py dict
into the canonical DB schema (destinations + emergency_contacts + zones tables).

Run once after first deploy:
    python -m backend.seed_data

Safe to re-run — skips already-existing records.
"""
import sys, os

BACKEND_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(BACKEND_DIR)
for path in (BACKEND_DIR, PROJECT_ROOT):
    if path not in sys.path:
        sys.path.insert(0, path)

import uuid, json, datetime
import asyncio
from sqlalchemy import select

from app.db.session import AsyncSessionLocal, init_models
from app.models.database import Authority, Destination, EmergencyContact, Zone

SEED_AUTHORITY_ID = "AID-SYSTEM-SEED"   # placeholder authority for seeded data

DESTINATIONS = [
    {
        "id": "UK_KED_001", "state": "Uttarakhand", "name": "Kedarnath Temple",
        "district": "Rudraprayag", "altitude_m": 3553,
        "center_lat": 30.7352, "center_lng": 79.0669,
        "category": "Religious / High Altitude", "difficulty": "HIGH",
        "connectivity": "POOR", "best_season": "May–June, Sep–Oct",
        "warnings": [
            "Altitude sickness above 3500m — acclimatize at Gaurikund",
            "No connectivity beyond Kedarnath base camp",
            "Helicopter services may be suspended in bad weather",
            "Night stay prohibited beyond designated zones after 8 PM",
        ],
        "contacts": [
            {"label": "SDRF",         "phone": "0135-2559898"},
            {"label": "Local Police", "phone": "01364-233445"},
            {"label": "Hospital",     "phone": "01364-233001", "notes": "District Hospital Ukhimath"},
        ],
        "zones": [
            {"name": "Temple Grounds", "type": "SAFE",   "shape": "CIRCLE",
             "center_lat": 30.7352, "center_lng": 79.0669, "radius_m": 500},
            {"name": "Caution Perimeter", "type": "CAUTION", "shape": "CIRCLE",
             "center_lat": 30.7352, "center_lng": 79.0669, "radius_m": 1500},
            {"name": "Mandakini Glacier", "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.7420, "center_lng": 79.0680, "radius_m": 300},
        ],
    },
    {
        "id": "UK_TUN_002", "state": "Uttarakhand", "name": "Tungnath Temple",
        "district": "Rudraprayag", "altitude_m": 3680,
        "center_lat": 30.4826, "center_lng": 79.2178,
        "category": "Religious / Trek", "difficulty": "MODERATE",
        "connectivity": "VERY_POOR", "best_season": "May–Nov",
        "warnings": [
            "World's highest Shiva temple — sudden blizzards possible",
            "No network after Chopta village",
            "Trail closes in heavy snowfall — check SDMA alerts",
        ],
        "contacts": [
            {"label": "SDRF",    "phone": "0135-2559898"},
            {"label": "Hospital","phone": "CHC Ukhimath"},
        ],
        "zones": [
            {"name": "Temple Area", "type": "SAFE",   "shape": "CIRCLE",
             "center_lat": 30.4826, "center_lng": 79.2178, "radius_m": 300},
            {"name": "Chandrashila Summit", "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.4956, "center_lng": 79.2239, "radius_m": 200},
        ],
    },
    {
        "id": "UK_BAD_003", "state": "Uttarakhand", "name": "Badrinath Temple",
        "district": "Chamoli", "altitude_m": 3133,
        "center_lat": 30.7433, "center_lng": 79.4938,
        "category": "Religious / High Altitude", "difficulty": "MODERATE",
        "connectivity": "MODERATE", "best_season": "May–Nov",
        "warnings": [
            "Border zone — carry valid ID at all times",
            "Mana village is India's last village — ITBP checkpost present",
            "Flash flood risk in Alaknanda valley during monsoon",
        ],
        "contacts": [
            {"label": "SDRF",         "phone": "0135-2559898"},
            {"label": "Local Police", "phone": "01372-222200"},
            {"label": "Hospital",     "phone": "01381-222205", "notes": "CHC Badrinath"},
        ],
        "zones": [
            {"name": "Temple Town", "type": "SAFE",   "shape": "CIRCLE",
             "center_lat": 30.7433, "center_lng": 79.4938, "radius_m": 1000},
            {"name": "Mana Village Border", "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.7803, "center_lng": 79.5631, "radius_m": 500},
        ],
    },
    {
        "id": "UK_GAN_004", "state": "Uttarakhand", "name": "Gangotri Temple",
        "district": "Uttarkashi", "altitude_m": 3100,
        "center_lat": 30.9940, "center_lng": 78.9377,
        "category": "Religious / High Altitude", "difficulty": "MODERATE",
        "connectivity": "POOR", "best_season": "May–Nov",
        "warnings": [
            "Gaumukh trek requires permit from Forest Dept",
            "Night stay at Gaumukh prohibited",
            "Avalanche risk — check SDMA bulletin before proceeding",
        ],
        "contacts": [
            {"label": "SDRF",         "phone": "0135-2559898"},
            {"label": "Local Police", "phone": "01374-222221"},
            {"label": "Hospital",     "phone": "01374-222100", "notes": "District Hospital Uttarkashi"},
        ],
        "zones": [
            {"name": "Temple Grounds", "type": "SAFE",   "shape": "CIRCLE",
             "center_lat": 30.9940, "center_lng": 78.9377, "radius_m": 800},
            {"name": "Gaumukh Glacier", "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.9213, "center_lng": 79.0753, "radius_m": 400},
        ],
    },
    {
        "id": "UK_JIM_012", "state": "Uttarakhand", "name": "Jim Corbett National Park",
        "district": "Nainital", "altitude_m": 400,
        "center_lat": 29.5300, "center_lng": 78.7747,
        "category": "Wildlife / Nature", "difficulty": "LOW",
        "connectivity": "MODERATE", "best_season": "Oct–Jun",
        "warnings": [
            "MANDATORY guide for all core zone entry",
            "No walking inside park boundaries — vehicle only",
            "Tiger reserve — maintain strict silence protocols",
        ],
        "contacts": [
            {"label": "Local Police", "phone": "05947-251234"},
            {"label": "Hospital",     "phone": "District Hospital Ramnagar"},
        ],
        "zones": [
            {"name": "Core Zone", "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 29.5745, "center_lng": 78.9234, "radius_m": 2000},
            {"name": "Buffer Zone", "type": "CAUTION", "shape": "CIRCLE",
             "center_lat": 29.5300, "center_lng": 78.7747, "radius_m": 5000},
        ],
    },
    {
        "id": "ML_CHE_001", "state": "Meghalaya", "name": "Cherrapunji (Sohra)",
        "district": "East Khasi Hills", "altitude_m": 1484,
        "center_lat": 25.2799, "center_lng": 91.7208,
        "category": "Nature / Extreme Rainfall Zone", "difficulty": "MODERATE",
        "connectivity": "POOR", "best_season": "Oct-May",
        "warnings": [
            "Dense fog can reduce visibility to zero",
            "Flash flood risk during monsoon",
        ],
        "contacts": [
            {"label": "Police",  "phone": "100"},
            {"label": "Hospital","phone": "Civil Hospital Shillong"},
        ],
        "zones": [
            {"name": "Town Centre", "type": "SAFE", "shape": "CIRCLE",
             "center_lat": 25.2799, "center_lng": 91.7208, "radius_m": 1000},
        ],
    },
    {
        "id": "AR_TAW_001", "state": "Arunachal Pradesh", "name": "Tawang Monastery",
        "district": "Tawang", "altitude_m": 3048,
        "center_lat": 27.5859, "center_lng": 91.8661,
        "category": "Religious / High Altitude", "difficulty": "HIGH",
        "connectivity": "VERY_POOR", "best_season": "Mar-Jun, Sep-Oct",
        "warnings": [
            "Inner Line Permit (ILP) required",
            "Sudden snowstorms can block Sela Pass",
        ],
        "contacts": [
            {"label": "Police",  "phone": "03794-222221"},
            {"label": "Hospital","phone": "District Hospital Tawang"},
        ],
        "zones": [
            {"name": "Monastery Grounds", "type": "SAFE", "shape": "CIRCLE",
             "center_lat": 27.5859, "center_lng": 91.8661, "radius_m": 500},
        ],
    },
    {
        "id": "DEMO_SCE_001", "state": "Demo / Hackathon",
        "name": "Shivalik College of Engineering",
        "district": "Dehradun", "altitude_m": 640,
        "center_lat": 30.3524, "center_lng": 77.9001,
        "category": "Demo / Campus Safety", "difficulty": "LOW",
        "connectivity": "GOOD", "best_season": "Year-round",
        "warnings": ["Demo environment — not a real emergency zone"],
        "contacts": [
            {"label": "Campus Security", "phone": "0135-0000001"},
            {"label": "Medical",         "phone": "0135-0000002"},
            {"label": "SDRF Dehradun",   "phone": "0135-2559898"},
        ],
        "zones": [
            {"name": "Main Gate",           "type": "SAFE",       "shape": "CIRCLE",
             "center_lat": 30.3524, "center_lng": 77.9001, "radius_m": 50},
            {"name": "Campus Interior",     "type": "SAFE",       "shape": "CIRCLE",
             "center_lat": 30.3528, "center_lng": 77.9008, "radius_m": 200},
            {"name": "Parking/Sports",      "type": "CAUTION",    "shape": "CIRCLE",
             "center_lat": 30.3535, "center_lng": 77.9012, "radius_m": 100},
            {"name": "Construction Zone",   "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.3545, "center_lng": 77.8995, "radius_m": 80},
            {"name": "Northern Boundary",   "type": "RESTRICTED", "shape": "CIRCLE",
             "center_lat": 30.3548, "center_lng": 77.9008, "radius_m": 60},
        ],
    },
]


async def _seed_async():
    await init_models()
    now = datetime.datetime.now()
    seeded_dest = seeded_zone = seeded_contact = 0

    async with AsyncSessionLocal() as db:
        async with db.begin():
        # 0. Ensure the seed authority exists
            auth_exists = await db.scalar(
                select(Authority.authority_id).where(Authority.authority_id == SEED_AUTHORITY_ID)
            )
            if not auth_exists:
                db.add(
                    Authority(
                        authority_id=SEED_AUTHORITY_ID,
                        full_name="System Seed Authority",
                        badge_id="SYSTEM-SEED",
                        email="system-seed@saferoute.local",
                        password_hash="not_a_real_password",
                        status="active",
                        role="authority",
                    )
                )

            for d in DESTINATIONS:
                exists = await db.scalar(
                    select(Destination.id).where(Destination.id == d["id"])
                )

                if not exists:
                    db.add(
                        Destination(
                            id=d["id"],
                            state=d["state"],
                            name=d["name"],
                            district=d["district"],
                            altitude_m=d["altitude_m"],
                            center_lat=d["center_lat"],
                            center_lng=d["center_lng"],
                            category=d["category"],
                            difficulty=d["difficulty"],
                            connectivity=d["connectivity"],
                            best_season=d["best_season"],
                            warnings_json=json.dumps(d["warnings"]),
                            authority_id=SEED_AUTHORITY_ID,
                            is_active=True,
                        )
                    )
                    seeded_dest += 1

                # Contacts
                for c in d.get("contacts", []):
                    cid = f"EC-{d['id']}-{c['label'].replace(' ','_').upper()}"
                    contact_exists = await db.scalar(
                        select(EmergencyContact.id).where(EmergencyContact.id == cid)
                    )
                    if not contact_exists:
                        db.add(
                            EmergencyContact(
                                id=cid,
                                destination_id=d["id"],
                                label=c["label"],
                                phone=c["phone"],
                                notes=c.get("notes"),
                            )
                        )
                        seeded_contact += 1

                # Zones
                for z in d.get("zones", []):
                    zid = f"Z-{d['id']}-{z['name'].replace(' ','_').upper()[:20]}"
                    zone_exists = await db.scalar(
                        select(Zone.id).where(Zone.id == zid)
                    )
                    if not zone_exists:
                        db.add(
                            Zone(
                                id=zid,
                                destination_id=d["id"],
                                authority_id=SEED_AUTHORITY_ID,
                                name=z["name"],
                                type=z["type"],
                                shape=z["shape"],
                                center_lat=z.get("center_lat"),
                                center_lng=z.get("center_lng"),
                                radius_m=z.get("radius_m"),
                                polygon_json=json.dumps(z.get("polygon_points", [])),
                                is_active=True,
                                created_at=now,
                                updated_at=now,
                            )
                        )
                        seeded_zone += 1

    return seeded_dest, seeded_zone, seeded_contact


def seed():
    seeded_dest, seeded_zone, seeded_contact = asyncio.run(_seed_async())

    print(f"Seed complete: {seeded_dest} destinations, {seeded_zone} zones, {seeded_contact} contacts")


if __name__ == "__main__":
    seed()
