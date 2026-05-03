# backend/migrations/README.md
#
# SafeRoute — Database Migration Guide
# ======================================
# All schema changes MUST go through Alembic. Never run raw SQL ALTER TABLE.
#
# This is enforced via the PR checklist and CONTRIBUTING.md.

# ──────────────────────────────────────────────────────────────
# 📖 Quick Reference
# ──────────────────────────────────────────────────────────────

## Creating a New Migration

When you add, remove, or change a column in `app/models/database.py`,
create a migration immediately:

```bash
# From the backend/ directory:
alembic revision --autogenerate -m "brief_description_of_change"

# Examples:
alembic revision --autogenerate -m "add_soft_delete_to_tourists"
alembic revision --autogenerate -m "add_mesh_node_table"
alembic revision --autogenerate -m "add_tuid_index_to_sos_events"
```

The generated file appears in `migrations/versions/`. **Always review it before committing.**

## Applying Migrations

```bash
# Apply all pending migrations:
alembic upgrade head

# Or with make:
make migrate
```

## Rolling Back

```bash
# Roll back one migration:
alembic downgrade -1

# Roll back to a specific revision:
alembic downgrade <revision_id>

# Roll back everything (dev only!):
alembic downgrade base
```

## Viewing Migration Status

```bash
# Show current DB revision:
alembic current

# Show full migration history:
alembic history --verbose
```

# ──────────────────────────────────────────────────────────────
# ⚠️ Rules — Follow These Always
# ──────────────────────────────────────────────────────────────

1. **Never run raw SQL** `ALTER TABLE`, `CREATE TABLE`, or `DROP TABLE` in production.
2. **Every model change = one migration file.** Autogenerate catches most changes automatically.
3. **Test migrations both ways** before merging: `upgrade head` then `downgrade -1`.
4. **Never delete migration files** from `migrations/versions/`. They are the source of truth.
5. **Migrations are reviewed in PRs** — include the generated migration file in your PR diff.

# ──────────────────────────────────────────────────────────────
# 🗂️ Migration File Naming Convention
# ──────────────────────────────────────────────────────────────

Format: `<revision_id>_<short_description>.py`

Examples:
- `a1b2c3d4_add_soft_delete_to_tourists.py`
- `e5f6g7h8_add_mesh_node_table.py`
- `i9j0k1l2_add_tuid_index.py`

Keep descriptions short (3-5 words), snake_case, describing the schema change.

# ──────────────────────────────────────────────────────────────
# 🔐 Soft Delete Pattern
# ──────────────────────────────────────────────────────────────

SafeRoute uses soft deletes for tourist and zone records.
See `app/db/soft_delete.py` for the mixin and helper functions.

To add soft delete to a new model:

```python
# In app/models/database.py:
from app.db.soft_delete import SoftDeleteMixin

class NewModel(SoftDeleteMixin, Base):
    __tablename__ = "new_table"
    ...
```

Then generate a migration:

```bash
alembic revision --autogenerate -m "add_soft_delete_to_new_table"
```

In crud.py, use the helpers:

```python
from app.db.soft_delete import soft_delete, restore, query_active

# Delete (recoverable):
await soft_delete(db, tourist_obj)

# Query only active records:
tourists = await query_active(db, Tourist, destination_state="Uttarakhand")

# Recover:
await restore(db, tourist_obj)
```
