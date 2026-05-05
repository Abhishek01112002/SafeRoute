"""Add missing database indexes for performance

Revision ID: e7f8a9b0c1d2
Revises: d4e5f6a7b8c9
Create Date: 2026-05-05 10:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e7f8a9b0c1d2"  # pragma: allowlist secret
down_revision: Union[str, None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _index_exists(table, index):
    bind = op.get_bind()
    insp = sa.inspect(bind)
    indexes = [idx['name'] for idx in insp.get_indexes(table)]
    return index in indexes

def upgrade() -> None:
    """Add missing indexes for query performance (ISSUE #6)"""

    # Index on dispatch_status for filtering high-volume SOS queries
    if not _index_exists("sos_events", "idx_sos_dispatch_status"):
        op.create_index(
            "idx_sos_dispatch_status",
            "sos_events",
            ["dispatch_status"],
            unique=False
        )

    # Index on scanned_at for time-range queries on authority scan logs
    if not _index_exists("authority_scan_log", "idx_scan_log_scanned_at"):
        op.create_index(
            "idx_scan_log_scanned_at",
            "authority_scan_log",
            ["scanned_at"],
            unique=False
        )

    # Compound index on (tourist_id, timestamp) for location_pings
    # Enables efficient WHERE tourist_id=? AND timestamp>? queries
    if not _index_exists("location_pings", "idx_location_pings_tourist_timestamp"):
        op.create_index(
            "idx_location_pings_tourist_timestamp",
            "location_pings",
            ["tourist_id", "timestamp"],
            unique=False
        )


def downgrade() -> None:
    """Remove indexes if rollback needed"""
    op.drop_index("idx_sos_dispatch_status", table_name="sos_events")
    op.drop_index("idx_scan_log_scanned_at", table_name="authority_scan_log")
    op.drop_index("idx_location_pings_tourist_timestamp", table_name="location_pings")
