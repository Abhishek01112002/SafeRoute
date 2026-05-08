"""allow_locationless_sos

Revision ID: 1a2b3c4d5e6f
Revises: 0f1e2d3c4b5a
Create Date: 2026-05-08 00:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "1a2b3c4d5e6f"
down_revision: Union[str, None] = "0f1e2d3c4b5a"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(table: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(table)


def upgrade() -> None:
    for table in ("sos_events", "sos_dispatch_queue"):
        if not _table_exists(table):
            continue
        with op.batch_alter_table(table, schema=None) as batch_op:
            batch_op.alter_column("latitude", existing_type=sa.Float(), nullable=True)
            batch_op.alter_column("longitude", existing_type=sa.Float(), nullable=True)


def downgrade() -> None:
    # Do not force NOT NULL on existing production data; locationless SOS rows
    # may already exist after this migration.
    pass
