import sqlite3
import os

DB_PATH = "data/saferoute.db"

def migrate():
    if not os.path.exists(DB_PATH):
        print(f"Error: {DB_PATH} not found.")
        return

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # List of columns to add to the 'tourists' table
    # format: (column_name, type_definition)
    new_columns = [
        ("tuid", "TEXT"),
        ("document_number_hash", "TEXT"),
        ("date_of_birth", "TEXT DEFAULT '1970-01-01'"),
        ("nationality", "TEXT DEFAULT 'IN'"),
        ("migrated_from_legacy", "INTEGER DEFAULT 0"),
        ("photo_object_key", "TEXT"),
        ("document_object_key", "TEXT"),
        ("photo_base64_legacy", "TEXT"),
        ("qr_data", "TEXT"),
        ("blood_group", "TEXT"),
        ("updated_at", "DATETIME")
    ]

    for col_name, col_type in new_columns:
        try:
            print(f"Adding column {col_name}...")
            cursor.execute(f"ALTER TABLE tourists ADD COLUMN {col_name} {col_type}")
        except sqlite3.OperationalError as e:
            if "duplicate column name" in str(e):
                print(f"Column {col_name} already exists.")
            else:
                print(f"Error adding {col_name}: {e}")

    # Add tuid to sos_events and location_pings as well
    for table in ["sos_events", "location_pings"]:
        try:
            print(f"Adding tuid to {table}...")
            cursor.execute(f"ALTER TABLE {table} ADD COLUMN tuid TEXT")
        except sqlite3.OperationalError as e:
            print(f"Note for {table}: {e}")

    conn.commit()
    conn.close()
    print("Migration complete!")

if __name__ == "__main__":
    migrate()
