# app/db/sqlite_legacy.py
import sqlite3
import json
import os
import datetime
from collections import deque
from typing import Dict, List, Optional
from fastapi import WebSocket

# Database Path from environment or default
DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "data", "saferoute.db")
os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_db():
    with get_db() as conn:
        # 1. Base Tables (Flat Schema)
        conn.executescript("""
            CREATE TABLE IF NOT EXISTS authorities (
                authority_id   TEXT PRIMARY KEY,
                full_name      TEXT NOT NULL,
                designation    TEXT,
                department     TEXT,
                badge_id       TEXT UNIQUE,
                district       TEXT,
                state          TEXT,
                phone          TEXT,
                email          TEXT UNIQUE,
                password       TEXT NOT NULL,
                fcm_token      TEXT,
                status         TEXT DEFAULT 'active',
                role           TEXT DEFAULT 'authority',
                created_at     TEXT
            );

            CREATE TABLE IF NOT EXISTS tourists (
                tourist_id            TEXT PRIMARY KEY,
                tuid                  TEXT,
                full_name             TEXT NOT NULL,
                document_type         TEXT,
                document_number_hash  TEXT,
                date_of_birth         TEXT,
                nationality           TEXT,
                photo_base64_legacy   TEXT,
                photo_object_key      TEXT,
                document_object_key   TEXT,
                emergency_contact_name TEXT,
                emergency_contact_phone TEXT,
                trip_start_date       TEXT,
                trip_end_date         TEXT,
                destination_state     TEXT,
                qr_data               TEXT,
                connectivity_level    TEXT DEFAULT 'GOOD',
                offline_mode_required INTEGER DEFAULT 0,
                risk_level            TEXT DEFAULT 'LOW',
                blood_group           TEXT,
                migrated_from_legacy  INTEGER DEFAULT 0,
                created_at            TEXT,
                updated_at            TEXT
            );

            CREATE TABLE IF NOT EXISTS destinations (
                id             TEXT PRIMARY KEY,
                state          TEXT NOT NULL,
                name           TEXT NOT NULL,
                district       TEXT,
                altitude_m     INTEGER DEFAULT 0,
                center_lat     REAL,
                center_lng     REAL,
                category       TEXT,
                difficulty     TEXT DEFAULT 'LOW',
                connectivity   TEXT DEFAULT 'MODERATE',
                best_season    TEXT,
                warnings_json  TEXT DEFAULT '[]',
                authority_id   TEXT,
                is_active      INTEGER DEFAULT 1,
                FOREIGN KEY(authority_id) REFERENCES authorities(authority_id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS zones (
                id             TEXT PRIMARY KEY,
                destination_id TEXT NOT NULL,
                authority_id   TEXT,
                name           TEXT NOT NULL,
                type           TEXT NOT NULL,
                shape          TEXT NOT NULL DEFAULT 'CIRCLE',
                center_lat     REAL,
                center_lng     REAL,
                radius_m       REAL,
                polygon_json   TEXT DEFAULT '[]',
                is_active      INTEGER DEFAULT 1,
                created_at     TEXT,
                updated_at     TEXT,
                FOREIGN KEY(destination_id) REFERENCES destinations(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS sos_events (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                tourist_id    TEXT NOT NULL,
                latitude      REAL NOT NULL,
                longitude     REAL NOT NULL,
                trigger_type  TEXT DEFAULT 'MANUAL',
                timestamp     TEXT NOT NULL,
                status        TEXT DEFAULT 'ACTIVE',
                responded_by  TEXT,
                responded_at  TEXT,
                destination_id TEXT,
                is_synced     INTEGER DEFAULT 0,
                FOREIGN KEY(tourist_id) REFERENCES tourists(tourist_id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS location_logs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                tourist_id TEXT NOT NULL,
                latitude   REAL NOT NULL,
                longitude  REAL NOT NULL,
                speed_kmh  REAL,
                accuracy_meters REAL,
                zone_status TEXT,
                timestamp  TEXT NOT NULL,
                FOREIGN KEY(tourist_id) REFERENCES tourists(tourist_id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS emergency_contacts (
                id             TEXT PRIMARY KEY,
                destination_id TEXT NOT NULL,
                label          TEXT NOT NULL,
                phone          TEXT NOT NULL,
                notes          TEXT,
                FOREIGN KEY(destination_id) REFERENCES destinations(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_zones_dest    ON zones(destination_id, is_active);
            CREATE INDEX IF NOT EXISTS idx_loc_tourist   ON location_logs(tourist_id, timestamp);
            CREATE INDEX IF NOT EXISTS idx_sos_status    ON sos_events(status);
            CREATE INDEX IF NOT EXISTS idx_contacts_dest ON emergency_contacts(destination_id);
        """)

        # 2. Manual column migrations for existing tables
        _migrate_columns(conn, "tourists", {
            "tuid": "TEXT",
            "document_number_hash": "TEXT",
            "date_of_birth": "TEXT",
            "nationality": "TEXT",
            "photo_object_key": "TEXT",
            "document_object_key": "TEXT",
            "blood_group": "TEXT",
            "migrated_from_legacy": "INTEGER DEFAULT 0"
        })

        _migrate_columns(conn, "sos_events", {
            "status": "TEXT DEFAULT 'ACTIVE'",
            "responded_by": "TEXT",
            "responded_at": "TEXT",
            "destination_id": "TEXT",
            "is_synced": "INTEGER DEFAULT 0"
        })

        conn.commit()

def _migrate_columns(conn: sqlite3.Connection, table_name: str, columns: Dict[str, str]):
    cursor = conn.execute(f"PRAGMA table_info({table_name})")
    existing_cols = {row["name"] for row in cursor.fetchall()}
    for col_name, col_def in columns.items():
        if col_name not in existing_cols:
            try:
                conn.execute(f"ALTER TABLE {table_name} ADD COLUMN {col_name} {col_def}")
            except sqlite3.OperationalError as e:
                print(f"[!] Migration failed for {table_name}.{col_name}: {e}")

# --- Internal persistence helpers ---

def load_tourists() -> Dict[str, dict]:
    try:
        with get_db() as conn:
            rows = conn.execute("SELECT * FROM tourists").fetchall()
            result = {}
            for row in rows:
                data = dict(row)
                # Ensure tuid is always present (even if column was added via migration and is NULL)
                if 'tuid' not in data or data['tuid'] is None:
                    data['tuid'] = ""
                # Ensure photo keys are present
                if 'photo_object_key' not in data or data['photo_object_key'] is None:
                    data['photo_object_key'] = ""
                if 'document_object_key' not in data or data['document_object_key'] is None:
                    data['document_object_key'] = ""
                if 'is_synced' not in data:
                    data['is_synced'] = True
                result[row["tourist_id"]] = data
            return result
    except Exception:
        return {}

def save_tourist(tourist_id: str, data: dict):
    with get_db() as conn:
        # Filter data to only include columns that exist in the table
        cursor = conn.execute("PRAGMA table_info(tourists)")
        allowed_cols = {row["name"]: (row["notnull"], row["dflt_value"]) for row in cursor.fetchall()}

        # Normalize and filter
        fields = {k: v for k, v in data.items() if k in allowed_cols}
        fields["tourist_id"] = tourist_id

        # Fill in required fields that are missing
        DEFAULTS = {
            "full_name": "Unknown",
            "document_type": "AADHAAR",
            "document_number_hash": "-",
            "trip_start_date": datetime.datetime.now().isoformat(),
            "trip_end_date": datetime.datetime.now().isoformat(),
            "destination_state": "Unknown",
            "connectivity_level": "GOOD",
            "offline_mode_required": 0,
            "risk_level": "LOW",
            "migrated_from_legacy": 1
        }

        for col_name, (notnull, dflt) in allowed_cols.items():
            if notnull and col_name not in fields and dflt is None:
                fields[col_name] = DEFAULTS.get(col_name, "-")

        placeholders = ", ".join([f":{k}" for k in fields.keys()])
        columns = ", ".join(fields.keys())

        conn.execute(f"INSERT OR REPLACE INTO tourists ({columns}) VALUES ({placeholders})", fields)
        conn.commit()

def load_authorities() -> Dict[str, dict]:
    try:
        with get_db() as conn:
            rows = conn.execute("SELECT * FROM authorities").fetchall()
        return {row["authority_id"]: dict(row) for row in rows}
    except Exception:
        return {}

def save_authority(authority_id: str, data: dict):
    with get_db() as conn:
        cursor = conn.execute("PRAGMA table_info(authorities)")
        allowed_cols = {row["name"] for row in cursor.fetchall()}

        fields = {k: v for k, v in data.items() if k in allowed_cols}
        fields["authority_id"] = authority_id

        placeholders = ", ".join([f":{k}" for k in fields.keys()])
        columns = ", ".join(fields.keys())

        conn.execute(f"INSERT OR REPLACE INTO authorities ({columns}) VALUES ({placeholders})", fields)
        conn.commit()

def persist_sos(tourist_id: str, latitude: float, longitude: float, trigger_type: str):
    with get_db() as conn:
        conn.execute(
            """INSERT INTO sos_events (tourist_id, latitude, longitude, trigger_type, timestamp)
               VALUES (?, ?, ?, ?, ?)""",
            (tourist_id, latitude, longitude, trigger_type, datetime.datetime.now().isoformat()),
        )
        conn.commit()

def get_sos_events_legacy():
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM sos_events ORDER BY id DESC LIMIT 100"
        ).fetchall()
    return [dict(row) for row in rows]


# ---------------------------------------------------------------------------
# Authority Security & Login Tracking (Legacy SQLite)
# ---------------------------------------------------------------------------

def get_authority_by_badge(badge_id: str) -> Optional[dict]:
    """Get authority by badge ID."""
    try:
        with get_db() as conn:
            row = conn.execute(
                "SELECT * FROM authorities WHERE badge_id = ?",
                (badge_id,)
            ).fetchone()
        return dict(row) if row else None
    except Exception:
        return None

def increment_failed_logins(authority_id: str) -> None:
    """Increment failed login attempts for an authority."""
    with get_db() as conn:
        conn.execute(
            """UPDATE authorities
               SET failed_login_attempts = COALESCE(failed_login_attempts, 0) + 1
               WHERE authority_id = ?""",
            (authority_id,)
        )
        conn.commit()

def reset_failed_logins(authority_id: str) -> None:
    """Reset failed login attempts and update last login timestamp."""
    with get_db() as conn:
        conn.execute(
            """UPDATE authorities
               SET failed_login_attempts = 0,
                   last_login = ?
               WHERE authority_id = ?""",
            (datetime.datetime.now().isoformat(), authority_id)
        )
        conn.commit()


# --- In-memory runtime state ---
# Lazy-load on first use via sync_from_db or manual call
tourists_db: Dict[str, dict] = {}
authorities_db: Dict[str, dict] = {}

def sync_from_db():
    """Manually sync the in-memory cache from the SQLite file."""
    global tourists_db, authorities_db
    tourists_db.clear()
    tourists_db.update(load_tourists())
    authorities_db.clear()
    authorities_db.update(load_authorities())

# Rolling location log
location_logs: deque = deque(maxlen=10_000)

# Room registry for Group Tour (Websocket)
rooms: Dict[str, Dict[str, dict]] = {}
connections: Dict[str, List[WebSocket]] = {}
