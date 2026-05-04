"""add_sos_resolution_fields

Revision ID: d4e5f6a7b8c9
Revises: 8f6aab2fc336
Create Date: 2026-05-04 18:12:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, None] = "8f6aab2fc336"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    with op.batch_alter_table("sos_events", schema=None) as batch_op:
        batch_op.add_column(sa.Column("authority_response", sa.Text(), nullable=True))
        batch_op.add_column(sa.Column("resolved_at", sa.DateTime(), nullable=True))


def downgrade() -> None:
    with op.batch_alter_table("sos_events", schema=None) as batch_op:
        batch_op.drop_column("resolved_at")
        batch_op.drop_column("authority_response")
