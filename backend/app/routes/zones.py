# app/routes/zones.py
from fastapi import APIRouter

router = APIRouter()

@router.get("/active")
async def get_zones():
    """Returns static zones for demo/hackathon."""
    return [
        {"id": 1, "name": "Danger Zone A", "radius": 500, "lat": 26.1445, "lng": 91.7362, "type": "RESTRICTED"},
        {"id": 2, "name": "Safe Zone B", "radius": 1000, "lat": 26.1500, "lng": 91.7400, "type": "SAFE"},
    ]
