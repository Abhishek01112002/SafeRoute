"""Rename location_logs table to location_pings for ORM consistency

Revision ID: f8a9b0c1d2e3
Revises: e7f8a9b0c1d2
Create Date: 2026-05-05 10:05:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "f8a9b0c1d2e3"  # pragma: allowlist secret
down_revision: Union[str, None] = "e7f8a9b0c1d2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(table):
    bind = op.get_bind()
    insp = sa.inspect(bind)
    return insp.has_table(table)

def _index_exists(index_name):
    connection = op.get_bind()
    # SQLite-specific check for global index names
    result = connection.execute(
        sa.text("SELECT name FROM sqlite_master WHERE type='index' AND name=:name"),
        {"name": index_name}
    ).fetchone()
    return result is not None

def upgrade() -> None:
    """Rename location_logs table to location_pings (CRITICAL FIX #1)

    This fixes the mismatch where legacy code writes to location_logs but ORM reads from location_pings,
    causing data loss and consistency issues.
    """
    # SQLite uses rename_table via batch operations
    if _table_exists("location_logs") and not _table_exists("location_pings"):
        op.rename_table("location_logs", "location_pings")

    # Create or replace index on renamed table
    if _table_exists("location_pings"):
        if _index_exists("idx_loc_tourist"):
            op.drop_index("idx_loc_tourist", table_name="location_pings")

        op.create_index(
            "idx_loc_tourist",
            "location_pings",
            ["tourist_id", "timestamp"],
            unique=False
        )


def downgrade() -> None:
    """Rollback: rename back to location_logs"""
    op.drop_index("idx_loc_tourist", table_name="location_pings")
    op.rename_table("location_pings", "location_logs")

    # Recreate original index
    op.create_index(
        "idx_loc_tourist",
        "location_logs",
        ["tourist_id", "timestamp"],
        unique=False
    )
