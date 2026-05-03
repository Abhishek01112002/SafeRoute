# destinations_data.py
# Legacy hardcoded data used for initial config derivation.
# In production, this should be replaced by DB queries in tourist_config.py.

DESTINATIONS_DATA = {
    "Uttarakhand": {
        "destinations": [
            {
                "id": "UK_KED_001", "name": "Kedarnath Temple", "connectivity": "POOR", "difficulty": "HIGH",
                "geo_fence": {"restricted_zones_coords": [[30.7420, 79.0680, 300]]},
                "emergency_contacts": {"SDRF": "0135-2559898", "Police": "01364-233445"}
            },
            {
                "id": "UK_TUN_002", "name": "Tungnath Temple", "connectivity": "VERY_POOR", "difficulty": "MODERATE",
                "geo_fence": {"restricted_zones_coords": [[30.4956, 79.2239, 200]]},
                "emergency_contacts": {"SDRF": "0135-2559898", "Hospital": "CHC Ukhimath"}
            },
            {
                "id": "UK_BAD_003", "name": "Badrinath Temple", "connectivity": "MODERATE", "difficulty": "MODERATE",
                "geo_fence": {"restricted_zones_coords": [[30.7803, 79.5631, 500]]},
                "emergency_contacts": {"SDRF": "0135-2559898", "Police": "01372-222200"}
            },
            {
                "id": "UK_GAN_004", "name": "Gangotri Temple", "connectivity": "POOR", "difficulty": "MODERATE",
                "geo_fence": {"restricted_zones_coords": [[30.9213, 79.0753, 400]]},
                "emergency_contacts": {"SDRF": "0135-2559898", "Police": "01374-222221"}
            },
            {
                "id": "UK_JIM_012", "name": "Jim Corbett National Park", "connectivity": "MODERATE", "difficulty": "LOW",
                "geo_fence": {"restricted_zones_coords": [[29.5745, 78.9234, 2000]]},
                "emergency_contacts": {"Police": "05947-251234"}
            }
        ]
    },
    "Meghalaya": {
        "destinations": [
            {
                "id": "ML_CHE_001", "name": "Cherrapunji (Sohra)", "connectivity": "POOR", "difficulty": "MODERATE",
                "geo_fence": {"restricted_zones_coords": []},
                "emergency_contacts": {"Police": "100"}
            }
        ]
    },
    "Arunachal Pradesh": {
        "destinations": [
            {
                "id": "AR_TAW_001", "name": "Tawang Monastery", "connectivity": "VERY_POOR", "difficulty": "HIGH",
                "geo_fence": {"restricted_zones_coords": []},
                "emergency_contacts": {"Police": "03794-222221"}
            }
        ]
    },
    "Demo / Hackathon": {
        "destinations": [
            {
                "id": "DEMO_SCE_001", "name": "Shivalik College of Engineering", "connectivity": "GOOD", "difficulty": "LOW",
                "geo_fence": {"restricted_zones_coords": [[30.3545, 77.8995, 80], [30.3548, 77.9008, 60]]},
                "emergency_contacts": {"Security": "0135-0000001", "Medical": "0135-0000002"}
            }
        ]
    }
}
