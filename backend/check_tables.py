import sqlite3, glob
dbs = glob.glob('**/*.db', recursive=True) + glob.glob('**/*.sqlite', recursive=True)
print('DB files found:', dbs)
for db_path in dbs[:2]:
    con = sqlite3.connect(db_path)
    tables = con.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").fetchall()
    print(f'\n{db_path} tables:')
    for t in tables:
        print(' -', t[0])
    con.close()
