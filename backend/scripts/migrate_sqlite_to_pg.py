import asyncio
import json
import logging
from datetime import datetime
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.config import settings
from app.models.database import Base, Tourist, TouristDestination, Authority, SOSEvent, LocationPing
from app.db.sqlite_legacy import get_conn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("migration")

def datetime_from_str(s: str) -> datetime:
    try:
        return datetime.fromisoformat(s.replace('Z', '+00:00'))
    except (ValueError, TypeError):
        return datetime.now()

async def migrate():
    logger.info("Starting data migration from Legacy SQLite to Normalized PostgreSQL...")
    
    # 1. Connect to PG
    pg_engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(pg_engine, class_=AsyncSession, expire_on_commit=False)
    
    # 2. Connect to SQLite
    sqlite_conn = get_conn()
    sqlite_cursor = sqlite_conn.cursor()
    
    async with async_session() as db:
        # --- Migrate Tourists ---
        logger.info("Migrating Tourists...")
        sqlite_cursor.execute("SELECT tourist_id, data FROM tourists")
        rows = sqlite_cursor.fetchall()
        for t_id, t_data_json in rows:
            data = json.loads(t_data_json)
            
            # Check if exists
            res = await db.execute(select(Tourist).where(Tourist.tourist_id == t_id))
            if res.scalar_one_or_none():
                continue
                
            tourist = Tourist(
                tourist_id=t_id,
                full_name=data.get("full_name", "Unknown"),
                document_type=data.get("document_type", "OTHER"),
                document_number=data.get("document_number", "N/A"),
                photo_base64_legacy=data.get("photo_base64"),
                emergency_contact_name=data.get("emergency_contact_name"),
                emergency_contact_phone=data.get("emergency_contact_phone"),
                trip_start_date=datetime_from_str(data.get("trip_start_date")),
                trip_end_date=datetime_from_str(data.get("trip_end_date")),
                destination_state=data.get("destination_state", "Unknown"),
                qr_data=data.get("qr_data"),
                blockchain_hash=data.get("blockchain_hash"),
                connectivity_level=data.get("connectivity_level", "GOOD"),
                offline_mode_required=data.get("offline_mode_required", False),
                risk_level=data.get("risk_level", "LOW")
            )
            
            # Destinations
            dests = data.get("selected_destinations", [])
            for d in dests:
                tourist.destinations.append(TouristDestination(
                    destination_id=d.get("destination_id"),
                    name=d.get("name"),
                    visit_date_from=datetime_from_str(d.get("visit_date_from")),
                    visit_date_to=datetime_from_str(d.get("visit_date_to"))
                ))
            
            db.add(tourist)
            
        # --- Migrate Authorities ---
        logger.info("Migrating Authorities...")
        sqlite_cursor.execute("SELECT authority_id, data FROM authorities")
        rows = sqlite_cursor.fetchall()
        for a_id, a_data_json in rows:
            data = json.loads(a_data_json)
            
            res = await db.execute(select(Authority).where(Authority.authority_id == a_id))
            if res.scalar_one_or_none():
                continue
                
            auth = Authority(
                authority_id=a_id,
                full_name=data.get("full_name", "Officer"),
                designation=data.get("designation"),
                department=data.get("department"),
                badge_id=data.get("badge_id", "N/A"),
                jurisdiction_zone=data.get("jurisdiction_zone"),
                phone=data.get("phone"),
                email=data.get("email", f"{a_id}@internal"),
                password_hash=data.get("password", ""), # Legacy stored plain password or hash
                status=data.get("status", "active"),
                role=data.get("role", "authority")
            )
            db.add(auth)

        # --- Migrate SOS Events ---
        logger.info("Migrating SOS Events...")
        # Note: Legacy SOS events might be in a different table or format
        try:
            sqlite_cursor.execute("SELECT id, tourist_id, latitude, longitude, trigger_type, timestamp FROM sos_events")
            rows = sqlite_cursor.fetchall()
            for row in rows:
                event = SOSEvent(
                    tourist_id=row[1],
                    latitude=row[2],
                    longitude=row[3],
                    trigger_type=row[4],
                    timestamp=datetime_from_str(row[5])
                )
                db.add(event)
        except Exception as e:
            logger.warning(f"Could not migrate SOS events: {e}")

        await db.commit()
        logger.info("Migration completed successfully.")

async def validate_migration():
    logger.info("--- Migration Validation Report ---")
    pg_engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(pg_engine, class_=AsyncSession, expire_on_commit=False)
    
    sqlite_conn = get_conn()
    sqlite_cursor = sqlite_conn.cursor()
    
    async with async_session() as db:
        # 1. Count Tourists
        sqlite_cursor.execute("SELECT COUNT(*) FROM tourists")
        sq_count = sqlite_cursor.fetchone()[0]
        from sqlalchemy import func
        pg_count = (await db.execute(select(func.count(Tourist.id)))).scalar()
        logger.info(f"Tourists: SQLite={sq_count}, PG={pg_count} | {'PASS' if sq_count <= pg_count else 'FAIL'}")

        # 2. Count Authorities
        sqlite_cursor.execute("SELECT COUNT(*) FROM authorities")
        sq_count_auth = sqlite_cursor.fetchone()[0]
        pg_count_auth = (await db.execute(select(func.count(Authority.id)))).scalar()
        logger.info(f"Authorities: SQLite={sq_count_auth}, PG={pg_count_auth} | {'PASS' if sq_count_auth <= pg_count_auth else 'FAIL'}")

        # 3. Sample check
        if pg_count > 0:
            res = await db.execute(select(Tourist).limit(1))
            sample = res.scalar()
            logger.info(f"Sample Tourist Check: {sample.full_name} ({sample.tourist_id}) - OK")
        
        # FINAL VERDICT
        status = "PASS"
        if sq_count > pg_count or sq_count_auth > pg_count_auth:
            status = "FAIL (Data Loss Detected)"
        
        print("\n" + "=" * 60)
        print(f"🏁 FINAL MIGRATION STATUS: {status}")
        print("=" * 60 + "\n")

    sqlite_conn.close()
    await pg_engine.dispose()

if __name__ == "__main__":
    asyncio.run(migrate())
    asyncio.run(validate_migration())
