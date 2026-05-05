import os
import sys

sys.path.append(os.path.join(os.getcwd(), "app"))
sys.path.append(os.getcwd())

from app.services.jwt_service import (
    JWT_ALGORITHM,
    PRIVATE_KEY,
    PUBLIC_KEY,
    create_jwt_token,
    verify_jwt_payload,
)

print(f"JWT_ALGORITHM: {JWT_ALGORITHM}")
if JWT_ALGORITHM == "RS256":
    print("PRIVATE_KEY looks like RSA: ", PRIVATE_KEY.startswith("-----BEGIN"))
    print("PUBLIC_KEY looks like RSA: ", PUBLIC_KEY.startswith("-----BEGIN"))
else:
    print("FALLBACK TO HS256")

token = create_jwt_token("test_user")
print(f"Token generated: {token[:20]}...")
payload = verify_jwt_payload(token)
print(f"Payload verified: {payload}")
if payload:
    print("[OK] JWT Service working correctly")
else:
    print("[FAIL] JWT Service FAILED self-test")
