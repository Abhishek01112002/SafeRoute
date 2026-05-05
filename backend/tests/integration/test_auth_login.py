import asyncio
import sys
import os

BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, BACKEND_DIR)

from app.db.session import AsyncSessionLocal
from app.db.session import engine
from app.db.crud import get_authority_by_email
from app.core import pwd_context

async def main():
    async with AsyncSessionLocal() as db:
        auth = await get_authority_by_email(db, 'admin@saferoute.com')
        print(f"Auth found: {auth}")
        if auth:
            stored_hash = auth.get('password_hash') or auth.get('password')
            print(f"Stored hash: {stored_hash}")
            is_valid = pwd_context.verify('Admin@SafeRoute123', stored_hash)
            print(f"Password valid: {is_valid}")
            print(f"Status: {auth.get('status')}")
    await engine.dispose()

if __name__ == '__main__':
    asyncio.run(main())
