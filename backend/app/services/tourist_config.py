# app/services/tourist_config.py
from typing import List
from app.models.schemas import DestinationVisit
from destinations_data import DESTINATIONS_DATA

def derive_tourist_config(selected_destinations: List[DestinationVisit], state: str) -> dict:
    """
    Derive connectivity/risk config from selected destinations.
    """
    safe_defaults = {
        "connectivity_level": "GOOD",
        "offline_mode_required": False,
        "geo_fence_zones": [],
        "emergency_contacts": {},
        "risk_level": "LOW",
    }

    if not selected_destinations:
        return safe_defaults

    state_data = DESTINATIONS_DATA.get(state, {}).get("destinations", [])
    dest_map = {d["id"]: d for d in state_data}

    all_dest_metadata = []
    for sd in selected_destinations:
        if sd.destination_id in dest_map:
            all_dest_metadata.append(dest_map[sd.destination_id])

    if not all_dest_metadata:
        return safe_defaults

    connectivity_rank = {
        "EXCELLENT": 5, "GOOD": 4, "MODERATE": 3,
        "POOR": 2, "VERY_POOR": 1, "NONE": 0,
    }

    worst_dest = min(
        all_dest_metadata,
        key=lambda d: connectivity_rank.get(d.get("connectivity", "GOOD"), 5),
    )

    geo_fences = []
    for d in all_dest_metadata:
        gf = d.get("geo_fence", {})
        geo_fences.extend(gf.get("restricted_zones_coords", []))

    contacts = {d["id"]: d.get("emergency_contacts", {}) for d in all_dest_metadata}

    difficulty_rank = {"LOW": 1, "MODERATE": 2, "HIGH": 3, "VERY_HIGH": 4}
    highest_risk_dest = max(
        all_dest_metadata,
        key=lambda d: difficulty_rank.get(d.get("difficulty", "LOW"), 0),
    )

    worst_connectivity = worst_dest.get("connectivity", "GOOD")
    return {
        "connectivity_level": worst_connectivity,
        "offline_mode_required": connectivity_rank.get(worst_connectivity, 5) <= 2,
        "geo_fence_zones": geo_fences,
        "emergency_contacts": contacts,
        "risk_level": highest_risk_dest.get("difficulty", "LOW"),
    }
