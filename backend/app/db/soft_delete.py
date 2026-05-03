# app/db/soft_delete.py
#
# SafeRoute Soft Delete Mixin
# ----------------------------
# Add this mixin to any SQLAlchemy model to enable safe, recoverable deletion.
# Records are NEVER physically deleted — they are flagged with is_deleted=True
# and a deleted_at timestamp. All queries automatically exclude deleted records
# when using the provided helper methods.
#
# Usage:
#   class Tourist(SoftDeleteMixin, Base):
#       __tablename__ = "tourists"
#       ...
#
# Then in crud.py:
#   await soft_delete(db, tourist_obj)       # instead of db.delete(obj)
#   results = await query_active(db, Tourist) # excludes deleted records
#
# To recover:
#   await restore(db, tourist_obj)

from datetime import datetime, timezone
from typing import Optional, Type, TypeVar
from sqlalchemy import Boolean, DateTime, func
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select


T = TypeVar("T", bound="SoftDeleteMixin")


class SoftDeleteMixin:
    """
    Mixin that adds soft-delete capability to any SQLAlchemy ORM model.
    Include this BEFORE Base in your model class declaration.

    Adds two columns:
      - is_deleted (Boolean, default False)
      - deleted_at (DateTime, nullable)
    """

    is_deleted: Mapped[bool] = mapped_column(
        Boolean,
        default=False,
        nullable=False,
        index=True,
        doc="If True, this record has been soft-deleted and should be excluded from normal queries."
    )
    deleted_at: Mapped[Optional[datetime]] = mapped_column(
        DateTime,
        nullable=True,
        default=None,
        doc="Timestamp when this record was soft-deleted. NULL means not deleted."
    )


# ---------------------------------------------------------------------------
# CRUD Helpers
# ---------------------------------------------------------------------------

async def soft_delete(db: AsyncSession, obj: SoftDeleteMixin) -> None:
    """
    Mark a record as deleted. Does NOT physically remove from DB.
    Always use this instead of db.delete() for soft-deletable models.
    """
    obj.is_deleted = True
    obj.deleted_at = datetime.now(timezone.utc)
    await db.commit()


async def restore(db: AsyncSession, obj: SoftDeleteMixin) -> None:
    """
    Recover a previously soft-deleted record.
    """
    obj.is_deleted = False
    obj.deleted_at = None
    await db.commit()


async def query_active(
    db: AsyncSession,
    model: Type[T],
    **filters
) -> list[T]:
    """
    Query only non-deleted records.
    Equivalent to: SELECT * FROM table WHERE is_deleted = FALSE AND <filters>

    Example:
        tourists = await query_active(db, Tourist, destination_state="Uttarakhand")
    """
    stmt = select(model).where(model.is_deleted == False)
    for attr, value in filters.items():
        stmt = stmt.where(getattr(model, attr) == value)
    result = await db.execute(stmt)
    return list(result.scalars().all())


async def query_deleted(
    db: AsyncSession,
    model: Type[T],
) -> list[T]:
    """
    Query ONLY soft-deleted records (for admin/audit purposes).
    """
    stmt = select(model).where(model.is_deleted == True)
    result = await db.execute(stmt)
    return list(result.scalars().all())
