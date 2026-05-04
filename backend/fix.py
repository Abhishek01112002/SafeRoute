import sqlite3
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import update
import sys

# Hardcoded PostgreSQL URL from .env
DB_URL = 'postgresql+asyncpg://postgres.hcsmypvaolyphuacgfbs:Anshuman%40SafeRoute@aws-1-ap-northeast-1.pooler.supabase.com:6543/postgres'

# Import the Zone model from app
sys.path.append('.')
from app.models.database import Zone

engine = create_async_engine(
    DB_URL,
    connect_args={
        'prepared_statement_cache_size': 0,
        'statement_cache_size': 0
    }
)

async def fix_zones():
    sqlite_conn = sqlite3.connect('saferoute.db')
    sqlite_conn.row_factory = sqlite3.Row
    rows = sqlite_conn.execute('SELECT * FROM zones').fetchall()
    
    AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    
    async with AsyncSessionLocal() as pg_session:
        for row in rows:
            print(f"Updating {row['id']} with {row['shape']}")
            await pg_session.execute(
                update(Zone)
                .where(Zone.id == row['id'])
                .values(shape=row['shape'], polygon_json=row['polygon_json'])
            )
        await pg_session.commit()
    print('Zones updated!')

asyncio.run(fix_zones())
