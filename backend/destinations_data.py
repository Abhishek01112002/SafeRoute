# backend/destinations_data.py

DESTINATIONS_DATA = {
    "Uttarakhand": {
        "priority": "PRIMARY",
        "destinations": [
            {
                "id": "UK_KED_001",
                "name": "Kedarnath Temple",
                "district": "Rudraprayag",
                "altitude_m": 3553,
                "coordinates": {"lat": 30.7352, "lon": 79.0669},
                "category": "Religious / High Altitude",
                "difficulty": "HIGH",
                "connectivity": "POOR",
                "best_season": "May–June, Sep–Oct",
                "restricted_zones": ["Mandakini Glacier", "Above Bhairavnath Temple"],
                "emergency_contacts": {
                    "sdrf": "0135-2559898",
                    "local_police": "01364-233445",
                    "hospital": "District Hospital Ukhimath: 01364-233001"
                },
                "geo_fence": {
                    "safe_radius_km": 0.5,
                    "caution_radius_km": 1.5,
                    "restricted_zones_coords": [
                        {"lat": 30.7420, "lon": 79.0680},
                        {"lat": 30.7389, "lon": 79.0721}
                    ]
                },
                "warnings": [
                    "Altitude sickness above 3500m — acclimatize at Gaurikund",
                    "No connectivity beyond Kedarnath base camp",
                    "Helicopter services may be suspended in bad weather",
                    "Night stay prohibited beyond designated zones after 8 PM"
                ]
            },
            {
                "id": "UK_TUN_002",
                "name": "Tungnath Temple",
                "district": "Rudraprayag",
                "altitude_m": 3680,
                "coordinates": {"lat": 30.4826, "lon": 79.2178},
                "category": "Religious / Trek",
                "difficulty": "MODERATE",
                "connectivity": "VERY_POOR",
                "best_season": "May–Nov",
                "restricted_zones": ["Chandrashila Summit (above 4000m)"],
                "emergency_contacts": {
                    "sdrf": "0135-2559898",
                    "local_police": "01364-233445",
                    "hospital": "CHC Ukhimath"
                },
                "geo_fence": {
                    "safe_radius_km": 0.3,
                    "caution_radius_km": 1.0,
                    "restricted_zones_coords": [
                        {"lat": 30.4956, "lon": 79.2239}
                    ]
                },
                "warnings": [
                    "World's highest Shiva temple — sudden blizzards possible",
                    "No network after Chopta village",
                    "Trail closes in heavy snowfall — check SDMA alerts"
                ]
            },
            {
                "id": "UK_BAD_003",
                "name": "Badrinath Temple",
                "district": "Chamoli",
                "altitude_m": 3133,
                "coordinates": {"lat": 30.7433, "lon": 79.4938},
                "category": "Religious / High Altitude",
                "difficulty": "MODERATE",
                "connectivity": "MODERATE",
                "best_season": "May–Nov",
                "restricted_zones": ["Mana Village Border Area", "Vasudhara Falls trail post 4 PM"],
                "emergency_contacts": {
                    "sdrf": "0135-2559898",
                    "local_police": "01372-222200",
                    "hospital": "CHC Badrinath: 01381-222205"
                },
                "geo_fence": {
                    "safe_radius_km": 1.0,
                    "caution_radius_km": 3.0,
                    "restricted_zones_coords": [
                        {"lat": 30.7803, "lon": 79.5631}
                    ]
                },
                "warnings": [
                    "Border zone — carry valid ID at all times",
                    "Mana village is India's last village — ITBP checkpost present",
                    "Flash flood risk in Alaknanda valley during monsoon"
                ]
            },
            {
                "id": "UK_GAN_004",
                "name": "Gangotri Temple",
                "district": "Uttarkashi",
                "altitude_m": 3100,
                "coordinates": {"lat": 30.9940, "lon": 78.9377},
                "category": "Religious / High Altitude",
                "difficulty": "MODERATE",
                "connectivity": "POOR",
                "best_season": "May–Nov",
                "restricted_zones": ["Gaumukh Glacier (permit required)", "Tapovan meadows"],
                "emergency_contacts": {
                    "sdrf": "0135-2559898",
                    "local_police": "01374-222221",
                    "hospital": "District Hospital Uttarkashi: 01374-222100"
                },
                "geo_fence": {
                    "safe_radius_km": 0.8,
                    "caution_radius_km": 2.0,
                    "restricted_zones_coords": [
                        {"lat": 30.9213, "lon": 79.0753}
                    ]
                },
                "warnings": [
                    "Gaumukh trek requires permit from Forest Dept",
                    "Night stay at Gaumukh prohibited",
                    "Avalanche risk — check SDMA bulletin before proceeding"
                ]
            },
            {
                "id": "UK_JIM_012",
                "name": "Jim Corbett National Park",
                "district": "Nainital",
                "altitude_m": 400,
                "coordinates": {"lat": 29.5300, "lon": 78.7747},
                "category": "Wildlife / Nature",
                "difficulty": "LOW",
                "connectivity": "MODERATE",
                "best_season": "Oct–Jun",
                "restricted_zones": ["Core zone (jeep safari only)", "Dhikala zone (permit required)"],
                "emergency_contacts": {
                    "sdrf": "0135-2559898",
                    "local_police": "05947-251234",
                    "hospital": "District Hospital Ramnagar"
                },
                "geo_fence": {
                    "safe_radius_km": 0.0,
                    "caution_radius_km": 2.0,
                    "restricted_zones_coords": [
                        {"lat": 29.5745, "lon": 78.9234}
                    ]
                },
                "warnings": [
                    "MANDATORY guide for all core zone entry",
                    "No walking inside park boundaries — vehicle only",
                    "Tiger reserve — maintain strict silence protocols"
                ]
            }
        ]
    },
    "Meghalaya": {
        "priority": "HIGH",
        "destinations": [
            {
                "id": "ML_CHE_001",
                "name": "Cherrapunji (Sohra)",
                "district": "East Khasi Hills",
                "altitude_m": 1484,
                "coordinates": {"lat": 25.2799, "lon": 91.7208},
                "category": "Nature / Extreme Rainfall Zone",
                "difficulty": "MODERATE",
                "connectivity": "POOR",
                "best_season": "Oct-May",
                "emergency_contacts": {
                    "police": "100",
                    "hospital": "Civil Hospital Shillong"
                },
                "warnings": ["Dense fog can reduce visibility to zero", "Flash flood risk during monsoon"]
            }
        ]
    },
    "Arunachal Pradesh": {
        "priority": "HIGH",
        "destinations": [
            {
                "id": "AR_TAW_001",
                "name": "Tawang Monastery",
                "district": "Tawang",
                "altitude_m": 3048,
                "coordinates": {"lat": 27.5859, "lon": 91.8661},
                "category": "Religious / High Altitude",
                "difficulty": "HIGH",
                "connectivity": "VERY_POOR",
                "best_season": "Mar-Jun, Sep-Oct",
                "emergency_contacts": {
                    "police": "03794-222221",
                    "hospital": "District Hospital Tawang"
                },
                "warnings": ["Inner Line Permit (ILP) required", "Sudden snowstorms can block Sela Pass"]
            }
        ]
    },

    # ─────────────────────────────────────────────────────────────
    # DEMO / HACKATHON — Shivalik College of Engineering, Dehradun
    # Used for live on-ground demonstrations during hackathons.
    # Zones are manually mapped around the SCE campus.
    # ─────────────────────────────────────────────────────────────
    "Demo / Hackathon": {
        "priority": "DEMO",
        "destinations": [
            {
                "id": "DEMO_SCE_001",
                "name": "Shivalik College of Engineering",
                "district": "Dehradun",
                "altitude_m": 640,
                "coordinates": {"lat": 30.3524, "lon": 77.9001},
                "category": "Demo / Campus Safety",
                "difficulty": "LOW",
                "connectivity": "GOOD",
                "best_season": "Year-round",
                "restricted_zones": ["Construction Zone (North)", "Northern Boundary Wall", "Eastern Perimeter"],
                "emergency_contacts": {
                    "campus_security": "0135-0000001",
                    "medical": "0135-0000002",
                    "sdrf_dehradun": "0135-2559898"
                },
                "geo_fence": {
                    "safe_radius_km": 0.05,
                    "caution_radius_km": 0.15,
                    "restricted_zones_coords": [
                        {"lat": 30.3545, "lon": 77.8995},
                        {"lat": 30.3548, "lon": 77.9008},
                        {"lat": 30.3525, "lon": 77.9020}
                    ]
                },
                "zones_description": {
                    "SAFE": ["Main Gate", "Admin Block", "Auditorium", "Canteen", "Emergency Exit Gate"],
                    "CAUTION": ["Parking Lot", "Sports Ground", "Hostel Block", "Back Road"],
                    "RESTRICTED": ["Construction Zone", "Northern Boundary", "Eastern Perimeter"]
                }
            },
            {
                "id": "DEMO_CURRENT_LOC",
                "name": "📍 Current Location (Hackathon Demo)",
                "district": "Live GPS",
                "altitude_m": 0,
                "coordinates": {"lat": 0.0, "lon": 0.0},
                "category": "Demo / Live Location",
                "difficulty": "LOW",
                "connectivity": "GOOD",
                "best_season": "Year-round",
                "restricted_zones": [],
                "emergency_contacts": {
                    "local_emergency": "112"
                },
                "geo_fence": {
                    "safe_radius_km": 0.1,
                    "caution_radius_km": 0.5,
                    "restricted_zones_coords": []
                },
                "is_live_location": True
            }
        ]
    }
}
