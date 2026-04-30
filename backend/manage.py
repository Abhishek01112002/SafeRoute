"""
backend/manage.py
SafeRoute management CLI.

Usage:
  python manage.py seed                         — seed destinations, zones, contacts
  python manage.py export-graph <dest_id>       — print trail graph JSON for a destination
  python manage.py check-zone <lat> <lng> <id>  — debug zone lookup for a point
  python manage.py list-destinations [state]    — list all destinations (optionally filter by state)
  python manage.py create-authority             — interactive: create an authority account
"""

import sys
import os
import json
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from dotenv import load_dotenv
load_dotenv()


def cmd_seed():
    from backend.seed_data import seed
    seed()


def cmd_export_graph(dest_id: str):
    from backend.database import init_db, get_db
    init_db()
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM trail_graphs WHERE destination_id=?", (dest_id,)
        ).fetchone()
    if not row:
        print(f"No trail graph found for destination: {dest_id}")
        return
    graph = json.loads(row["graph_json"])
    print(json.dumps(graph, indent=2))
    print(f"\n[Summary] nodes={len(graph.get('nodes', []))} edges={len(graph.get('edges', []))}")


def cmd_check_zone(lat: float, lng: float, dest_id: str):
    from backend.database import init_db, get_db
    from backend.routers.zones import _parse_zone, _point_in_zone
    import json
    init_db()
    with get_db() as conn:
        rows = conn.execute(
            "SELECT * FROM zones WHERE destination_id=? AND is_active=1", (dest_id,)
        ).fetchall()

    if not rows:
        print(f"No zones configured for {dest_id}")
        return

    print(f"Checking ({lat}, {lng}) against {len(rows)} zones in {dest_id}:\n")
    matched = []
    for r in rows:
        z = _parse_zone(dict(r))
        inside = _point_in_zone(lat, lng, z)
        status = "✅ INSIDE" if inside else "   outside"
        print(f"  {status}  [{z['type']}] {z['name']}  ({z['shape']})")
        if inside:
            matched.append(z)

    print()
    if matched:
        priority = {"RESTRICTED": 3, "CAUTION": 2, "SAFE": 1}
        best = max(matched, key=lambda z: priority.get(z["type"], 0))
        print(f"→ Result: {best['type']} ({best['name']})")
    else:
        print("→ Result: UNKNOWN (point not in any zone)")


def cmd_list_destinations(state: str | None = None):
    from backend.database import init_db, get_db
    init_db()
    with get_db() as conn:
        if state:
            rows = conn.execute(
                "SELECT id, name, district, state, difficulty, connectivity, is_active FROM destinations WHERE state=?",
                (state,)
            ).fetchall()
        else:
            rows = conn.execute(
                "SELECT id, name, district, state, difficulty, connectivity, is_active FROM destinations"
            ).fetchall()
    if not rows:
        print("No destinations found.")
        return
    print(f"{'ID':<20} {'NAME':<30} {'STATE':<20} {'DIFFICULTY':<10} ACTIVE")
    print("-" * 90)
    for r in rows:
        active = "✅" if r["is_active"] else "❌"
        print(f"{r['id']:<20} {r['name']:<30} {r['state']:<20} {r['difficulty']:<10} {active}")


def cmd_create_authority():
    import bcrypt, uuid, datetime
    from backend.database import init_db, save_authority, load_authorities
    init_db()

    print("\n=== Create Authority Account ===")
    full_name   = input("Full name:     ").strip()
    designation = input("Designation:   ").strip() or "District Officer"
    department  = input("Department:    ").strip() or "Tourism Safety"
    badge_id    = input("Badge ID:      ").strip()
    district    = input("District:      ").strip()
    state       = input("State:         ").strip()
    phone       = input("Phone:         ").strip()
    email       = input("Email:         ").strip()
    import getpass
    password    = getpass.getpass("Password:      ")

    existing = load_authorities()
    for a in existing.values():
        if a["badge_id"] == badge_id:
            print(f"\nError: Badge ID {badge_id} already registered.")
            return
        if a["email"] == email:
            print(f"\nError: Email {email} already registered.")
            return

    aid    = f"AID-{uuid.uuid4().hex[:8].upper()}"
    hashed = bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
    data   = {
        "authority_id": aid, "full_name": full_name, "designation": designation,
        "department": department, "badge_id": badge_id, "district": district,
        "state": state, "phone": phone, "email": email, "password": hashed,
        "fcm_token": None, "status": "active", "role": "authority",
        "created_at": datetime.datetime.now().isoformat(),
    }
    save_authority(data)
    print(f"\n✅ Authority created: {aid}")
    print(f"   Jurisdiction: {district}, {state}")
    print(f"   Email: {email}")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return

    cmd = sys.argv[1]

    if cmd == "seed":
        cmd_seed()
    elif cmd == "export-graph":
        if len(sys.argv) < 3:
            print("Usage: python manage.py export-graph <destination_id>")
            return
        cmd_export_graph(sys.argv[2])
    elif cmd == "check-zone":
        if len(sys.argv) < 5:
            print("Usage: python manage.py check-zone <lat> <lng> <destination_id>")
            return
        cmd_check_zone(float(sys.argv[2]), float(sys.argv[3]), sys.argv[4])
    elif cmd == "list-destinations":
        state = sys.argv[2] if len(sys.argv) > 2 else None
        cmd_list_destinations(state)
    elif cmd == "create-authority":
        cmd_create_authority()
    else:
        print(f"Unknown command: {cmd}")
        print(__doc__)


if __name__ == "__main__":
    main()
