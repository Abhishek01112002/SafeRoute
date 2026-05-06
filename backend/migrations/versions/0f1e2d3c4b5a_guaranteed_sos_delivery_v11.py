"""guaranteed_sos_delivery_v11

Revision ID: 0f1e2d3c4b5a
Revises: f8a9b0c1d2e3
Create Date: 2026-05-07 11:00:00.000000
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "0f1e2d3c4b5a"
down_revision: Union[str, None] = "f8a9b0c1d2e3"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _table_exists(table: str) -> bool:
    return sa.inspect(op.get_bind()).has_table(table)


def _column_exists(table: str, column: str) -> bool:
    insp = sa.inspect(op.get_bind())
    if not insp.has_table(table):
        return False
    return column in {col["name"] for col in insp.get_columns(table)}


def _index_exists(table: str, index_name: str) -> bool:
    insp = sa.inspect(op.get_bind())
    if not insp.has_table(table):
        return False
    return index_name in {idx["name"] for idx in insp.get_indexes(table)}


def _unique_exists(table: str, constraint_name: str) -> bool:
    insp = sa.inspect(op.get_bind())
    if not insp.has_table(table):
        return False
    return constraint_name in {uc["name"] for uc in insp.get_unique_constraints(table)}


def upgrade() -> None:
    for column, type_ in [
        ("idempotency_key", sa.String(length=80)),
        ("source", sa.String(length=20)),
        ("incident_status", sa.String(length=30)),
        ("delivery_state", sa.String(length=30)),
        ("delivery_summary", sa.Text()),
        ("relayed_by_tourist_id", sa.String(length=30)),
        ("acknowledged_at", sa.DateTime()),
        ("acknowledged_by", sa.String(length=30)),
    ]:
        if not _column_exists("sos_events", column):
            with op.batch_alter_table("sos_events", schema=None) as batch_op:
                batch_op.add_column(sa.Column(column, type_, nullable=True))

    if not _unique_exists("sos_events", "uq_sos_tourist_idempotency"):
        with op.batch_alter_table("sos_events", schema=None) as batch_op:
            batch_op.create_unique_constraint(
                "uq_sos_tourist_idempotency",
                ["tourist_id", "idempotency_key"],
            )
    if not _index_exists("sos_events", "ix_sos_incident_status"):
        op.create_index("ix_sos_incident_status", "sos_events", ["incident_status"])

    if not _table_exists("sos_dispatch_queue"):
        op.create_table(
            "sos_dispatch_queue",
            sa.Column("queue_id", sa.String(length=36), primary_key=True),
            sa.Column("sos_event_id", sa.Integer(), sa.ForeignKey("sos_events.id", ondelete="CASCADE"), nullable=False),
            sa.Column("tourist_id", sa.String(length=30), nullable=False),
            sa.Column("tuid", sa.String(length=24), nullable=True),
            sa.Column("idempotency_key", sa.String(length=80), nullable=True),
            sa.Column("latitude", sa.Float(), nullable=False),
            sa.Column("longitude", sa.Float(), nullable=False),
            sa.Column("trigger_type", sa.String(length=30), nullable=True),
            sa.Column("state", sa.String(length=30), nullable=True),
            sa.Column("attempt_count", sa.Integer(), nullable=True),
            sa.Column("next_attempt_at", sa.DateTime(), nullable=True),
            sa.Column("ttl_expires_at", sa.DateTime(), nullable=False),
            sa.Column("delivered_at", sa.DateTime(), nullable=True),
            sa.Column("escalated_at", sa.DateTime(), nullable=True),
            sa.Column("last_error", sa.Text(), nullable=True),
            sa.Column("claimed_at", sa.DateTime(), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
        )
        op.create_index("ix_sos_queue_due", "sos_dispatch_queue", ["state", "next_attempt_at"])
        op.create_index("ix_sos_queue_event", "sos_dispatch_queue", ["sos_event_id"])

    if not _table_exists("sos_delivery_audit"):
        op.create_table(
            "sos_delivery_audit",
            sa.Column("audit_id", sa.String(length=36), primary_key=True),
            sa.Column("sos_event_id", sa.Integer(), sa.ForeignKey("sos_events.id", ondelete="CASCADE"), nullable=False),
            sa.Column("queue_id", sa.String(length=36), sa.ForeignKey("sos_dispatch_queue.queue_id"), nullable=True),
            sa.Column("channel", sa.String(length=30), nullable=False),
            sa.Column("target", sa.String(length=255), nullable=True),
            sa.Column("status", sa.String(length=30), nullable=False),
            sa.Column("provider_status", sa.String(length=80), nullable=True),
            sa.Column("error_message", sa.Text(), nullable=True),
            sa.Column("attempt_number", sa.Integer(), nullable=True),
            sa.Column("timestamp", sa.DateTime(), server_default=sa.func.now(), nullable=True),
        )
        op.create_index("ix_sos_audit_event", "sos_delivery_audit", ["sos_event_id", "timestamp"])

    if not _table_exists("sos_provider_circuit"):
        op.create_table(
            "sos_provider_circuit",
            sa.Column("provider", sa.String(length=40), primary_key=True),
            sa.Column("state", sa.String(length=20), nullable=True),
            sa.Column("failure_count", sa.Integer(), nullable=True),
            sa.Column("opened_until", sa.DateTime(), nullable=True),
            sa.Column("last_failure_at", sa.DateTime(), nullable=True),
            sa.Column("last_success_at", sa.DateTime(), nullable=True),
            sa.Column("updated_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
        )

    if not _table_exists("tourist_mesh_keys"):
        op.create_table(
            "tourist_mesh_keys",
            sa.Column("id", sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column("tourist_id", sa.String(length=30), sa.ForeignKey("tourists.tourist_id", ondelete="CASCADE"), nullable=False),
            sa.Column("tuid", sa.String(length=24), nullable=False),
            sa.Column("tuid_suffix", sa.String(length=4), nullable=False),
            sa.Column("key_version", sa.Integer(), nullable=True),
            sa.Column("status", sa.String(length=20), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
            sa.Column("revoked_at", sa.DateTime(), nullable=True),
            sa.Column("grace_expires_at", sa.DateTime(), nullable=True),
            sa.UniqueConstraint("tourist_id", "key_version", name="uq_mesh_key_tourist_version"),
        )
        op.create_index("ix_mesh_key_tuid_suffix", "tourist_mesh_keys", ["tuid_suffix"])

    if not _table_exists("authority_devices"):
        op.create_table(
            "authority_devices",
            sa.Column("id", sa.String(length=36), primary_key=True),
            sa.Column("authority_id", sa.String(length=30), sa.ForeignKey("authorities.authority_id", ondelete="CASCADE"), nullable=False),
            sa.Column("fcm_token", sa.Text(), nullable=False),
            sa.Column("platform", sa.String(length=30), nullable=True),
            sa.Column("created_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
            sa.Column("last_seen_at", sa.DateTime(), server_default=sa.func.now(), nullable=True),
            sa.UniqueConstraint("authority_id", "fcm_token", name="uq_authority_device_token"),
        )


def downgrade() -> None:
    for table in ["authority_devices", "tourist_mesh_keys", "sos_provider_circuit", "sos_delivery_audit", "sos_dispatch_queue"]:
        if _table_exists(table):
            op.drop_table(table)

    with op.batch_alter_table("sos_events", schema=None) as batch_op:
        if _index_exists("sos_events", "ix_sos_incident_status"):
            batch_op.drop_index("ix_sos_incident_status")
        if _unique_exists("sos_events", "uq_sos_tourist_idempotency"):
            batch_op.drop_constraint("uq_sos_tourist_idempotency", type_="unique")
        for column in [
            "acknowledged_by",
            "acknowledged_at",
            "relayed_by_tourist_id",
            "delivery_summary",
            "delivery_state",
            "incident_status",
            "source",
            "idempotency_key",
        ]:
            if _column_exists("sos_events", column):
                batch_op.drop_column(column)
