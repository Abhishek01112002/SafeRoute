# app/config.py
"""
Centralized settings for SafeRoute backend.
Loaded from environment variables with sensible defaults.
"""
import os
from dataclasses import dataclass, field
from typing import List, Optional


@dataclass
class Settings:
    """Application settings — loaded once at startup."""

    # ---------------------------------------------------------------------------
    # Feature Flags (FIX #1: Dual-DB toggle)
    # ---------------------------------------------------------------------------
    ENABLE_PG: bool = False
    ENABLE_DUAL_WRITE: bool = False
    READ_FROM_PG: bool = False
    ENABLE_PHOTO_STORAGE: bool = False

    # ---------------------------------------------------------------------------
    # Database & Retention
    # ---------------------------------------------------------------------------
    DATABASE_URL: str = "sqlite+aiosqlite:///./data/saferoute.db"
    RETENTION_DAYS_LOCATION: int = 30
    DB_POOL_SIZE: int = 5           # DEV: 5, STAGING: 10, PROD: 20-50
    DB_MAX_OVERFLOW: int = 5        # DEV: 5, STAGING: 10, PROD: 20
    DB_POOL_TIMEOUT: int = 30

    # ---------------------------------------------------------------------------
    # JWT
    # ---------------------------------------------------------------------------
    JWT_ACCESS_EXPIRY_MINUTES: int = 60
    JWT_REFRESH_EXPIRY_DAYS: int = 7
    JWT_SECRET: str = "unsafe-secret-development-only"

    # ---------------------------------------------------------------------------
    # Security
    # ---------------------------------------------------------------------------
    ALLOWED_ORIGINS: str = "http://localhost:3000,http://127.0.0.1:3000"

    # ---------------------------------------------------------------------------
    # Photo Storage
    # ---------------------------------------------------------------------------
    PHOTO_STORAGE_BACKEND: str = "disk"  # "disk" | "s3" | "cloudinary"
    PHOTO_UPLOAD_DIR: str = "uploads/photos"

    # ---------------------------------------------------------------------------
    # RS256 Keys
    # ---------------------------------------------------------------------------
    PRIVATE_KEY_PATH: str = ""
    PUBLIC_KEY_PATH: str = ""

    # ---------------------------------------------------------------------------
    # SOS
    # ---------------------------------------------------------------------------
    SOS_DISPATCH_WEBHOOK_URL: str = ""

    def __post_init__(self):
        """Override defaults from environment variables."""
        self.ENABLE_PG = os.getenv("ENABLE_PG", "false").lower() == "true"
        self.ENABLE_DUAL_WRITE = os.getenv("ENABLE_DUAL_WRITE", "false").lower() == "true"
        self.READ_FROM_PG = os.getenv("READ_FROM_PG", "false").lower() == "true"
        self.ENABLE_PHOTO_STORAGE = os.getenv("ENABLE_PHOTO_STORAGE", "false").lower() == "true"
        self.DATABASE_URL = os.getenv("DATABASE_URL", self.DATABASE_URL)
        self.RETENTION_DAYS_LOCATION = int(os.getenv("RETENTION_DAYS_LOCATION", "30"))
        self.DB_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", str(self.DB_POOL_SIZE)))
        self.DB_MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", str(self.DB_MAX_OVERFLOW)))
        self.DB_POOL_TIMEOUT = int(os.getenv("DB_POOL_TIMEOUT", str(self.DB_POOL_TIMEOUT)))
        self.JWT_ACCESS_EXPIRY_MINUTES = int(os.getenv("JWT_ACCESS_EXPIRY_MINUTES", str(self.JWT_ACCESS_EXPIRY_MINUTES)))
        self.JWT_REFRESH_EXPIRY_DAYS = int(os.getenv("JWT_REFRESH_EXPIRY_DAYS", str(self.JWT_REFRESH_EXPIRY_DAYS)))
        self.JWT_SECRET = os.getenv("JWT_SECRET", self.JWT_SECRET)
        self.ALLOWED_ORIGINS = os.getenv("ALLOWED_ORIGINS", self.ALLOWED_ORIGINS)
        self.PHOTO_STORAGE_BACKEND = os.getenv("PHOTO_STORAGE_BACKEND", self.PHOTO_STORAGE_BACKEND)
        self.PHOTO_UPLOAD_DIR = os.getenv("PHOTO_UPLOAD_DIR", self.PHOTO_UPLOAD_DIR)
        self.SOS_DISPATCH_WEBHOOK_URL = os.getenv("SOS_DISPATCH_WEBHOOK_URL", "")

        # Key paths default to sibling of this file's parent (backend/)
        backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        self.PRIVATE_KEY_PATH = os.getenv(
            "PRIVATE_KEY_PATH",
            os.path.join(backend_dir, "private_key.pem"),
        )
        self.PUBLIC_KEY_PATH = os.getenv(
            "PUBLIC_KEY_PATH",
            os.path.join(backend_dir, "public_key.pem"),
        )

    def validate(self):
        """Strict production-grade validation. Fails fast if misconfigured."""
        missing = []
        if self.DATABASE_URL == "sqlite+aiosqlite:///./test.db":
            # Warning only if not in production, but if READ_FROM_PG is true, this is an error
            if self.READ_FROM_PG:
                missing.append("DATABASE_URL (must be PostgreSQL when READ_FROM_PG is enabled)")
        
        is_production = os.getenv("ENVIRONMENT") == "production"

        if is_production and (not self.JWT_SECRET or self.JWT_SECRET in {
            "YOUR_SUPER_SECRET_KEY_CHANGE_ME",
            "unsafe-secret-development-only",
        }):
            missing.append("JWT_SECRET (security risk: default or missing)")

        if missing:
            import sys
            print("\n" + "!" * 60)
            print("🚨 CRITICAL CONFIGURATION ERROR")
            for m in missing:
                print(f"  - MISSING: {m}")
            print("!" * 60 + "\n")
            sys.exit("Fatal: Production environment validation failed.")

        if self.ENABLE_PG and "postgresql" not in self.DATABASE_URL:
            raise ValueError("ENABLE_PG is true but DATABASE_URL is not a PostgreSQL connection string.")
        
        if self.READ_FROM_PG and not self.ENABLE_PG:
            raise ValueError("READ_FROM_PG cannot be true if ENABLE_PG is false.")

        if not os.path.exists(self.PRIVATE_KEY_PATH) or not os.path.exists(self.PUBLIC_KEY_PATH):
            # We don't raise here yet to allow generate_keys.py to run, but in production we should
            if os.getenv("ENVIRONMENT") == "production":
                 raise FileNotFoundError(f"RS256 keys missing at {self.PRIVATE_KEY_PATH}")

    def get_allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.ALLOWED_ORIGINS.split(",") if o.strip()]


# Singleton — imported everywhere
settings = Settings()
