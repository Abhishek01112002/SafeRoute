# app/db/sqlite_legacy.py
import sqlite3
import json
import os
import datetime
import time
from collections import deque
from typing import Dict, List, Optional
from fastapi import WebSocket

# Database Path from environment or default
DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "saferoute.db")

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

# --- Internal persistence helpers ---

def load_tourists() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT tourist_id, data FROM tourists").fetchall()
    return {row["tourist_id"]: json.loads(row["data"]) for row in rows}

def save_tourist(tourist_id: str, data: dict):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO tourists (tourist_id, data) VALUES (?, ?)",
            (tourist_id, json.dumps(data)),
        )
        conn.commit()

def load_authorities() -> Dict[str, dict]:
    with get_db() as conn:
        rows = conn.execute("SELECT authority_id, data FROM authorities").fetchall()
    return {row["authority_id"]: json.loads(row["data"]) for row in rows}

def save_authority(authority_id: str, data: dict):
    with get_db() as conn:
        conn.execute(
            "INSERT OR REPLACE INTO authorities (authority_id, data) VALUES (?, ?)",
            (authority_id, json.dumps(data)),
        )
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

# --- In-memory runtime state ---
# Initialize DB first to ensure tables exist
init_db()

tourists_db: Dict[str, dict] = load_tourists()
authorities_db: Dict[str, dict] = load_authorities()

# Rolling location log
location_logs: deque = deque(maxlen=10_000)

# Room registry for Group Tour
rooms: Dict[str, Dict[str, dict]] = {}
connections: Dict[str, List[WebSocket]] = {}
