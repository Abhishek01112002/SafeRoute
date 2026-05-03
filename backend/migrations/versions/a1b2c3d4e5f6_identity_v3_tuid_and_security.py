"""identity_v3_tuid_and_security

Revision ID: a1b2c3d4e5f6
Revises: cb7bc0b62d51
Create Date: 2026-05-01 22:00:00.000000

CRITICAL MIGRATION — Zero plaintext window:
  1. Add document_number_hash, tuid, date_of_birth, nationality columns
  2. Backfill: compute hash from existing document_number (Python fallback for SQLite)
  3. Backfill: compute TUID using placeholder DOB=1970-01-01, nationality=IN
  4. DROP document_number column (same transaction, no plaintext window)
  5. Add photo_object_key, migrated_from_legacy
  6. Extend qr_data to TEXT
  7. Add tuid column to sos_events and location_pings
  8. Create authority_scan_log table
"""
from typing import Sequence, Union
import hashlib
import datetime

from alembic import op
import sqlalchemy as sa
from sqlalchemy import text

# revision identifiers
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = 'cb7bc0b62d51'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

# Salt must match identity_service.py and identity_service.dart
_TUID_SALT = "SR_IDENTITY_V1_UTTARAKHAND_2025"
_PLACEHOLDER_DOB = "1970-01-01"
_PLACEHOLDER_NATIONALITY = "IN"


def _compute_tuid(doc_type: str, doc_number: str) -> str:
    """Deterministic TUID using placeholder DOB and nationality for backfill."""
    raw = f"{doc_type}:{doc_number}:{_PLACEHOLDER_DOB}:{_PLACEHOLDER_NATIONALITY}:{_TUID_SALT}"
    first = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    second = hashlib.sha256(first.encode("utf-8")).hexdigest()
    year = datetime.datetime.now().strftime("%y")
    suffix = second[:12].upper()
    return f"SR-{_PLACEHOLDER_NATIONALITY}-{year}-{suffix}"


def _hash_doc_number(doc_number: str) -> str:
    return hashlib.sha256(doc_number.encode("utf-8")).hexdigest()


def upgrade() -> None:
    conn = op.get_bind()

    # -------------------------------------------------------------------------
    # Enable pgcrypto if on PostgreSQL (needed for native SHA-256 functions)
    # -------------------------------------------------------------------------
    dialect = conn.dialect.name
    if dialect == "postgresql":
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS pgcrypto;"))

    # -------------------------------------------------------------------------
    # 1. Add new columns to tourists
    # -------------------------------------------------------------------------
    with op.batch_alter_table("tourists", schema=None) as batch_op:
        batch_op.add_column(sa.Column("tuid", sa.String(24), nullable=True))
        batch_op.add_column(sa.Column("document_number_hash", sa.Text(), nullable=True))
        batch_op.add_column(sa.Column("date_of_birth", sa.String(10), nullable=True, server_default="1970-01-01"))
        batch_op.add_column(sa.Column("nationality", sa.String(2), nullable=True, server_default="IN"))
        batch_op.add_column(sa.Column("migrated_from_legacy", sa.Boolean(), nullable=False, server_default="1"))
        batch_op.add_column(sa.Column("photo_object_key", sa.Text(), nullable=True))
        # Extend qr_data from String(255) to Text
        batch_op.alter_column("qr_data", type_=sa.Text(), existing_nullable=True)

    # -------------------------------------------------------------------------
    # 2. Backfill: hash document_number + compute TUID for every existing tourist
    #    CRITICAL: This runs BEFORE dropping document_number.
    # -------------------------------------------------------------------------
    tourists_rows = conn.execute(
        text("SELECT tourist_id, document_type, document_number FROM tourists")
    ).fetchall()

    seen_tuids: set = set()

    for row in tourists_rows:
        tourist_id = row[0]
        doc_type = row[1] or "AADHAAR"
        doc_number = row[2] or ""

        doc_hash = _hash_doc_number(doc_number)
        tuid = _compute_tuid(doc_type, doc_number)

        # Handle extremely rare TUID collision for legacy data
        if tuid in seen_tuids:
            # Suffix with first 4 chars of doc_hash for disambiguation
            tuid = tuid[:-4] + doc_hash[:4].upper()
        seen_tuids.add(tuid)

        conn.execute(
            text("""
                UPDATE tourists
                SET document_number_hash = :hash,
                    tuid = :tuid,
                    date_of_birth = :dob,
                    nationality = :nat,
                    migrated_from_legacy = :migrated
                WHERE tourist_id = :tid
            """),
            {
                "hash": doc_hash,
                "tuid": tuid,
                "dob": _PLACEHOLDER_DOB,
                "nat": _PLACEHOLDER_NATIONALITY,
                "migrated": True,
                "tid": tourist_id,
            }
        )

    # -------------------------------------------------------------------------
    # 3. Make document_number_hash NOT NULL (after backfill)
    #    Then DROP document_number — ZERO PLAINTEXT WINDOW within same transaction
    # -------------------------------------------------------------------------
    with op.batch_alter_table("tourists", schema=None) as batch_op:
        batch_op.alter_column("document_number_hash", nullable=False)
        batch_op.drop_column("document_number")
        batch_op.create_index("ix_tourists_tuid", ["tuid"], unique=True)
        batch_op.create_index("ix_tourists_doc_hash", ["document_number_hash"], unique=False)

    # -------------------------------------------------------------------------
    # 4. Add tuid column to sos_events and location_pings
    # -------------------------------------------------------------------------
    with op.batch_alter_table("sos_events", schema=None) as batch_op:
        batch_op.add_column(sa.Column("tuid", sa.String(24), nullable=True))
        batch_op.create_index("ix_sos_events_tuid", ["tuid"], unique=False)

    with op.batch_alter_table("location_pings", schema=None) as batch_op:
        batch_op.add_column(sa.Column("tuid", sa.String(24), nullable=True))
        batch_op.create_index("ix_location_pings_tuid", ["tuid"], unique=False)

    # -------------------------------------------------------------------------
    # 5. Create authority_scan_log table
    # -------------------------------------------------------------------------
    op.create_table(
        "authority_scan_log",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("authority_id", sa.String(30), sa.ForeignKey("authorities.authority_id"), nullable=False, index=True),
        sa.Column("scanned_tuid", sa.String(24), nullable=False, index=True),
        sa.Column("tourist_id", sa.String(30), sa.ForeignKey("tourists.tourist_id"), nullable=True),
        sa.Column("scanned_at", sa.DateTime(), server_default=sa.text("(CURRENT_TIMESTAMP)"), nullable=False, index=True),
        sa.Column("ip_address", sa.String(45), nullable=True),
        sa.Column("user_agent", sa.Text(), nullable=True),
        sa.Column("photo_url_generated", sa.Boolean(), nullable=False, server_default="0"),
    )


def downgrade() -> None:
    # Drop audit log
    op.drop_table("authority_scan_log")

    # Remove tuid from sos_events and location_pings
    with op.batch_alter_table("location_pings", schema=None) as batch_op:
        batch_op.drop_index("ix_location_pings_tuid")
        batch_op.drop_column("tuid")

    with op.batch_alter_table("sos_events", schema=None) as batch_op:
        batch_op.drop_index("ix_sos_events_tuid")
        batch_op.drop_column("tuid")

    # Restore tourists (add document_number back, drop new columns)
    with op.batch_alter_table("tourists", schema=None) as batch_op:
        batch_op.add_column(sa.Column("document_number", sa.String(50), nullable=True))
        batch_op.drop_index("ix_tourists_doc_hash")
        batch_op.drop_index("ix_tourists_tuid")
        batch_op.drop_column("photo_object_key")
        batch_op.drop_column("migrated_from_legacy")
        batch_op.drop_column("nationality")
        batch_op.drop_column("date_of_birth")
        batch_op.drop_column("document_number_hash")
        batch_op.drop_column("tuid")
        batch_op.alter_column("qr_data", type_=sa.String(255), existing_nullable=True)
