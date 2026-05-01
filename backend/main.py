"""
backend/main.py
SafeRoute API — v2.0
All business logic lives in routers/. This file is pure orchestration.
"""
import os, datetime
from dotenv import load_dotenv

env_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path=env_path)  # must be before any module that reads env vars

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from backend.database import init_db
from backend.routers import authorities, destinations, zones, trail_graphs, tourists, sos, location, rooms

# ── CORS ──────────────────────────────────────────────────────────────────────
_raw_origins = os.getenv("CORS_ORIGINS", "")
ALLOWED_ORIGINS = [o.strip() for o in _raw_origins.split(",") if o.strip()] or ["*"]

app = FastAPI(title="SafeRoute API", version="2.0.0", docs_url="/docs")

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Startup ───────────────────────────────────────────────────────────────────
@app.on_event("startup")
def startup():
    init_db()
    print(f"[SafeRoute] DB initialised. CORS origins: {ALLOWED_ORIGINS}")

# ── Routers ───────────────────────────────────────────────────────────────────
app.include_router(authorities.router)
app.include_router(destinations.router)
app.include_router(zones.router)
app.include_router(trail_graphs.router)
app.include_router(tourists.router)
app.include_router(sos.router)
app.include_router(location.router)
app.include_router(rooms.router)

# ── Health ────────────────────────────────────────────────────────────────────
@app.get("/health", tags=["System"])
async def health():
    from backend.database import get_db
    with get_db() as conn:
        tourist_count   = conn.execute("SELECT COUNT(*) FROM tourists").fetchone()[0]
        authority_count = conn.execute("SELECT COUNT(*) FROM authorities").fetchone()[0]
        sos_active      = conn.execute("SELECT COUNT(*) FROM sos_events WHERE status='ACTIVE'").fetchone()[0]
    return {
        "status":          "ok",
        "timestamp":       datetime.datetime.now().isoformat(),
        "version":         "2.0.0",
        "tourists":        tourist_count,
        "authorities":     authority_count,
        "active_sos":      sos_active,
    }


# ── Auth token refresh ────────────────────────────────────────────────────────
from fastapi import Security as _Security
from backend.auth import require_tourist as _req_tourist, create_token as _create_token

@app.post("/auth/refresh", tags=["Auth"])
async def refresh_token(tourist_id: str = _Security(_req_tourist)):
    token = _create_token(tourist_id, role="tourist")
    return {"token": token, "expires_in": 86400}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("backend.main:app", host="0.0.0.0", port=8000, reload=True)
