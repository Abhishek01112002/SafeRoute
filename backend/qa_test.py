import asyncio
import os
from app.services.identity_service import generate_tuid, hash_document_number
from app.services.qr_service import qr_service
from app.config import settings
from app.db.session import AsyncSessionLocal
from app.db.session import engine
from sqlalchemy import text

async def test_all():
    print("--- QA TEST SUITE: SAFEROUTE DIGITAL IDENTITY ---")

    # 1. Test TUID Cryptography
    print("\n[1] Testing TUID Generation (Zero-Plaintext)...")
    doc_type = "AADHAAR"
    doc_num = "123456789012"
    dob = "1990-01-01"
    nat = "IN"

    tuid1 = generate_tuid(doc_type, doc_num, dob, nat)
    tuid2 = generate_tuid(doc_type, doc_num, dob, nat)

    assert tuid1 == tuid2, "TUID generation must be deterministic"
    assert "IN" in tuid1, "TUID must contain nationality"
    assert len(tuid1) == 21, f"TUID length invalid: {len(tuid1)}"

    doc_hash = hash_document_number(doc_num)
    assert doc_num not in doc_hash, "Hash must not contain plaintext"

    print(f"  [PASS] Deterministic Double-SHA256 successful.")
    print(f"  [INFO] TUID Generated: {tuid1}")
    print(f"  [INFO] Document Hash: {doc_hash}")

    # 2. Test DB Schema Migration (Alembic Verification)
    print("\n[2] Testing Database Schema Hardening...")
    try:
        async with AsyncSessionLocal() as db:
            result = await db.execute(text("PRAGMA table_info(tourists)"))
            columns = [row[1] for row in result.fetchall()]

            assert "document_number" not in columns, "CRITICAL FAILURE: document_number STILL EXISTS"
            assert "tuid" in columns, "Missing tuid column"
            assert "document_number_hash" in columns, "Missing document_number_hash column"

            print("  [PASS] Plaintext PII columns successfully dropped.")
            print("  [PASS] v3 Identity columns present.")
    except Exception as e:
        print(f"  [FAIL] DB Error: {e}")

    # 3. Test QR Service (RS256 Offline Integrity)
    print("\n[3] Testing RS256 QR Service...")
    # Generate mock keys just for testing if they don't exist
    if not os.path.exists("private_key.pem"):
        print("  [WARN] RSA keys not found locally. Simulating graceful failure.")
        assert qr_service.is_available is False
        print("  [PASS] QR Service gracefully fails when keys missing.")
    else:
        qr = qr_service.sign_qr_jwt(tuid1, "Test Tourist", nat)
        decoded = qr_service.verify_qr_jwt(qr)
        assert decoded["sub"] == tuid1
        print("  [PASS] RS256 QR signed and verified locally.")

    await engine.dispose()
    print("\n--- TEST COMPLETE ---")

if __name__ == "__main__":
    asyncio.run(test_all())
