import asyncio
from app.db.session import AsyncSessionLocal
from app.routes.tourist import register_tourist
from app.models.schemas import TouristRegister
from fastapi import Request

class MockRequest:
    pass

async def run():
    payload = TouristRegister(
        full_name="Test Tourist",
        document_type="AADHAAR",
        document_number="999988887777",
        emergency_contact_name="Mom",
        emergency_contact_phone="1234567890",
        trip_start_date="2026-05-01",
        trip_end_date="2026-05-15",
        destination_state="Uttarakhand"
    )
    async with AsyncSessionLocal() as db:
        res = await register_tourist(request=MockRequest(), tourist=payload, db=db)
        print("Success:", res)

asyncio.run(run())
