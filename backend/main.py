from fastapi import FastAPI, HTTPException, Body, WebSocket, WebSocketDisconnect, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import HTTPBearer, HTTPAuthCredentials
from pydantic import BaseModel, field_validator
from typing import List, Optional, Dict
import datetime
import uuid
import json
import time
import bcrypt
import sqlite3
import os
from collections import deque
from destinations_data import DESTINATIONS_DATA
import jwt
from functools import wraps

app = FastAPI(title="SafeRoute API", version="1.0.0")

# ---------------------------------------------------------------------------
# CORS — allow the Flutter app on the same LAN and any localhost dev origin
# ---------------------------------------------------------------------------
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # tighten to specific IPs before production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# JWT CONFIGURATION (HACKATHON — use simple secret, production needs improvement)
# ---------------------------------------------------------------------------
JWT_SECRET = os.getenv("JWT_SECRET", "saferoute-hackathon-secret-key-2026")
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 24  # Token valid for 24 hours

security = HTTPBearer()

def create_jwt_token(tourist_id: str, expires_hours: int = JWT_EXPIRATION_HOURS) -> str:
    """Generate JWT token for tourist"""
    payload = {
        "tourist_id": tourist_id,
        "exp": datetime.datetime.utcnow() + datetime.timedelta(hours=expires_hours),
        "iat": datetime.datetime.utcnow(),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm=JWT_ALGORITHM)

def verify_jwt_token(token: str) -> Optional[str]:
    """Verify JWT token and return tourist_id"""
    try:
        payload = jwt.decode(token, JWT_SECRET, algorithms=[JWT_ALGORITHM])
        return payload.get("tourist_id")
    except jwt.ExpiredSignatureError:
        return None  # Token expired
    except jwt.InvalidTokenError:
        return None  # Invalid token

async def get_current_tourist(credentials: HTTPAuthCredentials = Security(security)) -> str:
    """Dependency to get current tourist from JWT"""
    token = credentials.credentials
    tourist_id = verify_jwt_token(token)
    if not tourist_id:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return tourist_id

# ---------------------------------------------------------------------------
# SQLite persistence — survives server restarts
# ---------------------------------------------------------------------------
DB_PATH = os.path.join(os.path.dirname(__file__), "saferoute.db")


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    with get_db() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS tourists (
                tourist_id TEXT PRIMARY KEY,
                data       TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS authorities (
                authority_id TEXT PRIMARY KEY,
                data         TEXT NOT NULL
            )
        """)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS sos_events (
                id           INTEGER PRIMARY KEY AUTOINCREMENT,
                tourist_id   TEXT,
                latitude     REAL,
                longitude    REAL,
                trigger_type TEXT,
                timestamp    TEXT,
                is_synced    INTEGER DEFAULT 0
            )
        """)
        conn.commit()


init_db()


def _load_tourists() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT tourist_id, data FROM tourists").fetchall()
    return {row["tourist_id"]: json.loads(row["data"]) for row in rows}


def _save_tourist(tourist_id: str, data: dict):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO tourists (tourist_id, data) VALUES (?, ?)",
            (tourist_id, json.dumps(data)),
        )
        conn.commit()


def _load_authorities() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT authority_id, data FROM authorities").fetchall()
    return {row["authority_id"]: json.loads(row["data"]) for row in rows}


def _save_authority(authority_id: str, data: dict):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO authorities (authority_id, data) VALUES (?, ?)",
            (authority_id, json.dumps(data)),
        )
        conn.commit()


def _persist_sos(tourist_id: str, latitude: float, longitude: float, trigger_type: str):
    with get_db() as conn:
        conn.execute(
            """INSERT INTO sos_events (tourist_id, latitude, longitude, trigger_type, timestamp)
               VALUES (?, ?, ?, ?, ?)""",
            (tourist_id, latitude, longitude, trigger_type, datetime.datetime.now().isoformat()),
        )
        conn.commit()


# ---------------------------------------------------------------------------
# In-memory runtime state (backed by SQLite)
# ---------------------------------------------------------------------------
tourists_db: Dict[str, dict] = _load_tourists()
authorities_db: Dict[str, dict] = _load_authorities()

# Rolling location log — capped at 10,000 entries to prevent memory exhaustion
location_logs: deque = deque(maxlen=10_000)

# Room registry for Group Tour
rooms: Dict[str, Dict[str, dict]] = {}
connections: Dict[str, List[WebSocket]] = {}

# ---------------------------------------------------------------------------
# Data Models with validation
# ---------------------------------------------------------------------------


class DestinationVisit(BaseModel):
    destination_id: str
    name: str
    visit_date_from: str
    visit_date_to: str


class TouristRegister(BaseModel):
    full_name: str
    document_type: str
    document_number: str
    photo_base64: str
    emergency_contact_name: str
    emergency_contact_phone: str
    trip_start_date: str
    trip_end_date: str
    destination_state: str
    selected_destinations: List[DestinationVisit] = []

    @field_validator("full_name")
    @classmethod
    def name_not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("full_name cannot be empty")
        return v

    @field_validator("document_number")
    @classmethod
    def doc_number_valid(cls, v: str, info) -> str:
        v = v.strip()
        doc_type = info.data.get("document_type")
        import re
        if doc_type == "AADHAAR":
            if not re.match(r"^\d{12}$", v):
                raise ValueError("AADHAAR must be exactly 12 digits")
        elif doc_type == "PASSPORT":
            if not re.match(r"^[A-Z0-9]{8,12}$", v):
                raise ValueError("PASSPORT must be 8-12 alphanumeric characters")
        return v

    @field_validator("emergency_contact_phone")
    @classmethod
    def phone_valid(cls, v: str) -> str:
        digits = "".join(c for c in v if c.isdigit())
        if len(digits) < 7:
            raise ValueError("emergency_contact_phone must have at least 7 digits")
        return v

    @field_validator("photo_base64")
    @classmethod
    def photo_not_empty(cls, v: str) -> str:
        if not v or not v.strip():
            raise ValueError("photo_base64 is required")
        return v


class LocationPing(BaseModel):
    tourist_id: str
    latitude: float
    longitude: float
    speed_kmh: float
    accuracy_meters: float
    timestamp: str
    zone_status: str

    @field_validator("tourist_id")
    @classmethod
    def tourist_must_exist(cls, v: str) -> str:
        # Loaded lazily; basic format check only (full DB check done in endpoint)
        if not v or not v.strip():
            raise ValueError("tourist_id is required")
        return v


class AuthorityRegister(BaseModel):
    full_name: str
    designation: str
    department: str
    badge_id: str
    jurisdiction_zone: str
    phone: str
    email: str
    password: str

    @field_validator("full_name", "badge_id", "email")
    @classmethod
    def not_empty(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("Field cannot be empty")
        return v

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if len(v) < 6:
            raise ValueError("password must be at least 6 characters")
        return v


# ---------------------------------------------------------------------------
# Helper — derive tourist config
# ---------------------------------------------------------------------------

def derive_tourist_config(selected_destinations: List[DestinationVisit], state: str) -> dict:
    """
    Derive connectivity/risk config from selected destinations.
    Always returns a complete, safe dict (never empty).
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
        # Unknown destination IDs — return safe defaults instead of crashing
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


# ---------------------------------------------------------------------------
# Helper — safe authority view (no password)
# ---------------------------------------------------------------------------

def _safe_authority_view(auth: dict) -> dict:
    """Return authority dict without the hashed password."""
    return {k: v for k, v in auth.items() if k != "password"}


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
async def health_check():
    return {
        "status": "ok",
        "timestamp": datetime.datetime.now().isoformat(),
        "tourists": len(tourists_db),
        "authorities": len(authorities_db),
    }


# ---------------------------------------------------------------------------
# Destination APIs
# ---------------------------------------------------------------------------

@app.get("/destinations/states")
async def get_states():
    return list(DESTINATIONS_DATA.keys())


@app.get("/destinations/{state}")
async def get_destinations_by_state(state: str):
    if state not in DESTINATIONS_DATA:
        raise HTTPException(status_code=404, detail="State not found")
    return DESTINATIONS_DATA[state]["destinations"]


# ---------------------------------------------------------------------------
# Authority Auth
# ---------------------------------------------------------------------------

@app.post("/auth/register/authority")
async def register_authority(auth: AuthorityRegister):
    # Duplicate badge_id check
    for a in authorities_db.values():
        if a["badge_id"] == auth.badge_id:
            raise HTTPException(status_code=400, detail="Badge ID already registered")
    for a in authorities_db.values():
        if a["email"] == auth.email:
            raise HTTPException(status_code=400, detail="Email already registered")

    authority_id = f"AID-{uuid.uuid4().hex[:8].upper()}"

    # Hash password with bcrypt (FIX #1 — never store plain-text)
    hashed_pw = bcrypt.hashpw(auth.password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")

    auth_data = {
        "authority_id": authority_id,
        "full_name": auth.full_name,
        "designation": auth.designation,
        "department": auth.department,
        "badge_id": auth.badge_id,
        "jurisdiction_zone": auth.jurisdiction_zone,
        "phone": auth.phone,
        "email": auth.email,
        "password": hashed_pw,       # stored hashed
        "status": "active",
        "role": "authority",
        "created_at": datetime.datetime.now().isoformat(),
    }

    authorities_db[authority_id] = auth_data
    _save_authority(authority_id, auth_data)  # persist to SQLite

    # Generate JWT token for the authority
    token = create_jwt_token(authority_id)

    return {
        "message": "Registration successful. Account activated.",
        "authority_id": authority_id,
        "status": "active",
        "token": token,
    }


@app.post("/auth/login/authority")
async def login_authority(payload: dict = Body(...)):
    email = (payload.get("email") or "").strip()
    password = payload.get("password") or ""

    if not email or not password:
        raise HTTPException(status_code=400, detail="Email and password are required")

    for auth in authorities_db.values():
        if auth["email"] == email:
            stored_hash = auth.get("password", "")
            # FIX #2 — compare with bcrypt, never plain-text
            if bcrypt.checkpw(password.encode("utf-8"), stored_hash.encode("utf-8")):
                # Generate token on login
                token = create_jwt_token(auth["authority_id"])
                # FIX #3 — never return the password field
                response_data = _safe_authority_view(auth)
                response_data["token"] = token
                return response_data
            else:
                raise HTTPException(status_code=401, detail="Invalid email or password")

    raise HTTPException(status_code=401, detail="Invalid email or password")


# ---------------------------------------------------------------------------
# Tourist Registration
# ---------------------------------------------------------------------------

@app.post("/tourist/register")
async def register_tourist(tourist: TouristRegister):
    state_codes = {
        "Uttarakhand": "UK",
        "Meghalaya": "ML",
        "Arunachal Pradesh": "AR",
        "Assam": "AS",
    }
    state_code = state_codes.get(tourist.destination_state, "XX")
    year = datetime.datetime.now().year
    # FIX #4 — use UUID suffix to avoid race-condition duplicate IDs
    uid_suffix = uuid.uuid4().hex[:5].upper()
    tourist_id = f"TID-{year}-{state_code}-{uid_suffix}"

    config = derive_tourist_config(tourist.selected_destinations, tourist.destination_state)

    # Real SHA-256 hash of the tourist identity data
    import hashlib
    identity_payload = json.dumps({
        "tourist_id": tourist_id,
        "document_type": tourist.document_type,
        "document_number": tourist.document_number,
        "full_name": tourist.full_name,
    }, sort_keys=True)
    blockchain_hash = "0x" + hashlib.sha256(identity_payload.encode()).hexdigest()

    tourist_data = {
        "tourist_id": tourist_id,
        "full_name": tourist.full_name,
        "document_type": tourist.document_type,
        "document_number": tourist.document_number,
        "photo_base64": tourist.photo_base64,
        "emergency_contact_name": tourist.emergency_contact_name,
        "emergency_contact_phone": tourist.emergency_contact_phone,
        "trip_start_date": tourist.trip_start_date,
        "trip_end_date": tourist.trip_end_date,
        "destination_state": tourist.destination_state,
        "selected_destinations": [d.model_dump() for d in tourist.selected_destinations],
        "qr_data": f"SAFEROUTE-{tourist_id}",
        "created_at": datetime.datetime.now().isoformat(),
        "blockchain_hash": blockchain_hash,
        **config,
    }

    tourists_db[tourist_id] = tourist_data
    _save_tourist(tourist_id, tourist_data)  # persist to SQLite

    print(f"[REGISTER] Tourist: {tourist.full_name} ({tourist_id}) Risk: {config.get('risk_level')}")
    
    # Generate JWT token
    token = create_jwt_token(tourist_id)
    
    return {
        "tourist": tourist_data,
        "token": token,
        "expires_in": JWT_EXPIRATION_HOURS * 3600,  # In seconds
    }

# ---------------------------------------------------------------------------
# Tourist Login (retrieve existing registration)
# ---------------------------------------------------------------------------

class TouristLoginRequest(BaseModel):
    tourist_id: str

@app.post("/tourist/login")
async def login_tourist(request: TouristLoginRequest):
    """Login or retrieve tourist data by ID"""
    tourist_data = tourists_db.get(request.tourist_id)
    if not tourist_data:
        raise HTTPException(status_code=404, detail="Tourist not found")
    
    # Generate JWT token
    token = create_jwt_token(request.tourist_id)
    print(f"[LOGIN] Tourist: {request.tourist_id}")
    
    return {
        "tourist": tourist_data,
        "token": token,
        "expires_in": JWT_EXPIRATION_HOURS * 3600,
    }

# ---------------------------------------------------------------------------
# Token Refresh
# ---------------------------------------------------------------------------

@app.post("/auth/refresh")
async def refresh_token(tourist_id: str = Depends(get_current_tourist)):
    """Refresh JWT token"""
    token = create_jwt_token(tourist_id)
    return {
        "token": token,
        "expires_in": JWT_EXPIRATION_HOURS * 3600,
    }

# ---------------------------------------------------------------------------
# Location Ping
# ---------------------------------------------------------------------------

@app.post("/location/ping")
async def receive_ping(ping: LocationPing, tourist_id: str = Depends(get_current_tourist)):
    # JWT already validated by Depends, but verify it matches the ping
    if ping.tourist_id != tourist_id:
        raise HTTPException(status_code=403, detail="Tourist ID mismatch")
    
    # Validate tourist exists
    if ping.tourist_id not in tourists_db:
        raise HTTPException(status_code=404, detail="Tourist ID not registered")

    # FIX #5 — deque automatically drops oldest entries when maxlen is exceeded
    location_logs.append(ping.model_dump())
    print(f"[PING] {ping.tourist_id}: ({ping.latitude:.5f}, {ping.longitude:.5f})"
          f" Speed:{ping.speed_kmh:.1f}km/h Zone:{ping.zone_status}")
    return {"status": "received"}


# ---------------------------------------------------------------------------
# SOS
# ---------------------------------------------------------------------------

@app.post("/sos/trigger")
async def trigger_sos(payload: dict = Body(...), tourist_id: str = Depends(get_current_tourist)):
    # JWT already validated, tourist_id from token
    latitude = payload.get("latitude")
    longitude = payload.get("longitude")
    trigger_type = payload.get("trigger_type", "MANUAL")

    if latitude is None or longitude is None:
        raise HTTPException(status_code=400, detail="latitude and longitude are required")

    # FIX #6 — persist SOS to SQLite instead of only printing
    _persist_sos(
        tourist_id=str(tourist_id),
        latitude=float(latitude),
        longitude=float(longitude),
        trigger_type=str(trigger_type),
    )

    # Log loudly so monitoring can pick it up
    print(f"[!!! SOS !!!] Tourist:{tourist_id} @ ({latitude}, {longitude}) Type:{trigger_type}")

    # TODO (production): integrate SMS gateway / push notification here
    return {
        "status": "alert_dispatched",
        "tourist_id": tourist_id,
        "timestamp": datetime.datetime.now().isoformat(),
    }


@app.get("/sos/events")
async def get_sos_events(tourist_id: str = Depends(get_current_tourist)):
    """Authority endpoint — list all SOS events. (Token required)"""
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM sos_events ORDER BY id DESC LIMIT 100"
        ).fetchall()
    return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Zones
# ---------------------------------------------------------------------------

@app.get("/zones/active")
async def get_zones():
    return [
        {"id": 1, "name": "Danger Zone A", "radius": 500, "lat": 26.1445, "lng": 91.7362, "type": "RESTRICTED"},
        {"id": 2, "name": "Safe Zone B", "radius": 1000, "lat": 26.1500, "lng": 91.7400, "type": "SAFE"},
    ]


# ---------------------------------------------------------------------------
# Group Tour — Room APIs
# ---------------------------------------------------------------------------

@app.post("/rooms/create")
async def create_room(tourist_id: str = Depends(get_current_tourist)):
    room_id = uuid.uuid4().hex[:6].upper()
    rooms[room_id] = {}
    connections[room_id] = []
    print(f"[ROOM] Created: {room_id} by {tourist_id}")
    return {"room_id": room_id}


@app.post("/rooms/{room_id}/join")
async def join_room(room_id: str, tourist_id: str = Depends(get_current_tourist)):
    if room_id not in rooms:
        raise HTTPException(status_code=404, detail="Room not found")
    return {"status": "ok", "room_id": room_id, "user_id": tourist_id}


# ---------------------------------------------------------------------------
# WebSocket — Group Location Sharing
# ---------------------------------------------------------------------------

@app.websocket("/ws/{room_id}/{user_id}")
async def room_websocket(websocket: WebSocket, room_id: str, user_id: str, token: Optional[str] = None):
    # Validate token from query param (WebSockets don't easily support headers in JS/Dart)
    if not token or verify_jwt_token(token) != user_id:
        await websocket.close(code=4003) # Forbidden
        return

    await websocket.accept()

    if room_id not in rooms:
        await websocket.close(code=4004)
        return

    if room_id not in connections:
        connections[room_id] = []
    connections[room_id].append(websocket)

    print(f"[WS] User {user_id} joined room {room_id}")

    try:
        while True:
            data = await websocket.receive_text()
            payload = json.loads(data)

            rooms[room_id][user_id] = {
                "user_id": user_id,
                "name": payload.get("name", "Unknown"),
                "lat": float(payload["lat"]),
                "lng": float(payload["lng"]),
                "timestamp": time.time(),
            }

            snapshot = list(rooms[room_id].values())
            broadcast = json.dumps({"type": "location_update", "members": snapshot})

            dead: List[WebSocket] = []
            for conn in connections[room_id]:
                try:
                    await conn.send_text(broadcast)
                except Exception:  # FIX #7 — bare except → Exception
                    dead.append(conn)

            for d in dead:
                connections[room_id].remove(d)

    except WebSocketDisconnect:
        if websocket in connections.get(room_id, []):
            connections[room_id].remove(websocket)
        rooms[room_id].pop(user_id, None)
        print(f"[WS] User {user_id} left room {room_id}")

        snapshot = list(rooms[room_id].values())
        broadcast = json.dumps({"type": "member_left", "user_id": user_id, "members": snapshot})
        for conn in connections.get(room_id, []):
            try:
                await conn.send_text(broadcast)
            except Exception:
                pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
