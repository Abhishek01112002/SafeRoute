import asyncio
import sys
sys.path.insert(0, '.')
from app.db import sqlite_legacy

def main():
    tourists = sqlite_legacy.load_tourists()
    print('=== SQLite File Data ===')
    for tid, data in list(tourists.items())[:3]:
        tuid = data.get('tuid', 'NOT_SET')
        photo = data.get('photo_object_key', 'NOT_SET')
        print(tid + ': tuid=' + str(tuid)[:30] + ', photo=' + str(photo)[:40])

if __name__ == '__main__':
    main()
