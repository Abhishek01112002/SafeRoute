# app/db/session.py
from contextlib import asynccontextmanager
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from app.config import settings
from app.models.database import Base

engine_options = {
    "pool_pre_ping": True,
    "echo": False,
}

if not settings.DATABASE_URL.startswith("sqlite"):
    engine_options.update(
        {
            "pool_size": settings.DB_POOL_SIZE,
            "max_overflow": settings.DB_MAX_OVERFLOW,
            "pool_timeout": settings.DB_POOL_TIMEOUT,
            "connect_args": {
                "prepared_statement_cache_size": 0,
                "statement_cache_size": 0
            },
        }
    )

# FIX #5: Environment-adaptive pool sizing
engine = create_async_engine(settings.DATABASE_URL, **engine_options)

# Async session factory
AsyncSessionLocal = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False
)

async def get_db():
    """
    FastAPI dependency for async DB sessions.
    FIX #6: Explicit transaction management via session.begin()
    """
    async with AsyncSessionLocal() as session:
        try:
            async with session.begin():
                yield session
        except Exception:
            # begin() automatically rollbacks on exception
            raise
        finally:
            await session.close()


@asynccontextmanager
async def db_session_context():
    """Context manager variant for startup tasks and maintenance jobs."""
    async with AsyncSessionLocal() as session:
        try:
            async with session.begin():
                yield session
        finally:
            await session.close()


async def init_models() -> None:
    """Create local SQLite tables for development and hackathon deployments."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        
        # Idempotent column additions for missing fields across environments
        ddl_statements = [
            "ALTER TABLE authorities ADD COLUMN email_verified BOOLEAN DEFAULT true",
            "ALTER TABLE sos_events ADD COLUMN group_id VARCHAR(36)",
        ]
        
        if engine.dialect.name == "sqlite":
            ddl_statements.extend([
                "ALTER TABLE sos_events ADD COLUMN authority_response TEXT",
                "ALTER TABLE sos_events ADD COLUMN resolved_at DATETIME",
            ])
            
        for ddl in ddl_statements:
            try:
                await conn.exec_driver_sql(ddl)
            except Exception:
                # Ignores errors if column already exists
                pass
