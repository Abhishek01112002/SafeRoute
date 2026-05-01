# backend/database.py
# Single source of truth for all DB operations.

import sqlite3, json, os
from typing import Dict

DB_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "saferoute.db")

def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn

def init_db():
    with get_db() as conn:
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
                FOREIGN KEY(authority_id) REFERENCES authorities(authority_id)
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
                FOREIGN KEY(destination_id) REFERENCES destinations(id)
            );

            CREATE TABLE IF NOT EXISTS trail_graphs (
                id             TEXT PRIMARY KEY,
                destination_id TEXT UNIQUE NOT NULL,
                version        INTEGER DEFAULT 1,
                graph_json     TEXT NOT NULL,
                created_at     TEXT,
                FOREIGN KEY(destination_id) REFERENCES destinations(id)
            );

            CREATE TABLE IF NOT EXISTS emergency_contacts (
                id              TEXT PRIMARY KEY,
                destination_id  TEXT NOT NULL,
                label           TEXT NOT NULL,
                phone           TEXT NOT NULL,
                secondary_phone TEXT,
                notes           TEXT,
                FOREIGN KEY(destination_id) REFERENCES destinations(id)
            );

            CREATE TABLE IF NOT EXISTS tourists (
                tourist_id TEXT PRIMARY KEY,
                data       TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS sos_events (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                tourist_id    TEXT,
                latitude      REAL,
                longitude     REAL,
                trigger_type  TEXT,
                timestamp     TEXT,
                status        TEXT DEFAULT 'ACTIVE',
                responded_by  TEXT,
                responded_at  TEXT,
                destination_id TEXT
            );

            CREATE TABLE IF NOT EXISTS location_logs (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                tourist_id TEXT,
                latitude   REAL,
                longitude  REAL,
                speed_kmh  REAL,
                zone_status TEXT,
                timestamp  TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_zones_dest    ON zones(destination_id, is_active);
            CREATE INDEX IF NOT EXISTS idx_sos_status    ON sos_events(status);
            CREATE INDEX IF NOT EXISTS idx_loc_tourist   ON location_logs(tourist_id, timestamp);
        """)
        conn.commit()

# ── Tourists helpers ──────────────────────────────────────────────────────────

def load_tourists() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT tourist_id, data FROM tourists").fetchall()
    return {r["tourist_id"]: json.loads(r["data"]) for r in rows}

def save_tourist(tourist_id: str, data: dict):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO tourists (tourist_id, data) VALUES (?,?)",
            (tourist_id, json.dumps(data))
        )
        conn.commit()

# ── Authorities helpers ───────────────────────────────────────────────────────

def load_authorities() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT * FROM authorities").fetchall()
    return {r["authority_id"]: dict(r) for r in rows}

def save_authority(data: dict):
    with get_db() as conn:
        conn.execute("""
            INSERT OR REPLACE INTO authorities
            (authority_id,full_name,designation,department,badge_id,district,state,
             phone,email,password,fcm_token,status,role,created_at)
            VALUES (:authority_id,:full_name,:designation,:department,:badge_id,:district,:state,
                    :phone,:email,:password,:fcm_token,:status,:role,:created_at)
        """, {**data, "fcm_token": data.get("fcm_token"), "district": data.get("district"), "state": data.get("state")})
        conn.commit()
