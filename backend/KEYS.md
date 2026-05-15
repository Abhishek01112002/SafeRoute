# SafeRoute RS256 Key Management

Last reviewed: 2026-05-16

SafeRoute Digital Identity uses RS256 asymmetric cryptography to sign QR JWTs. The backend signs QR payloads with a private RSA key; mobile and authority clients can verify QR payloads with the public key.

## Generate Keys

```powershell
cd backend
python generate_keys.py
```

This creates:

- `private_key.pem` - secret, never commit.
- `public_key.pem` - public verification key.

The repository `.gitignore` excludes `*.pem`.

## Configure Key Files

```env
PRIVATE_KEY_PATH=./private_key.pem
PUBLIC_KEY_PATH=./public_key.pem
```

If unset, the backend defaults to `backend/private_key.pem` and `backend/public_key.pem`.

## Configure Base64 PEMs

Hosted platforms can use environment variables instead of files:

```env
PRIVATE_KEY_BASE64=<base64-of-private-pem>
PUBLIC_KEY_BASE64=<base64-of-public-pem>
```

Startup validation confirms that these values decode to valid RSA PEM material.

## Public Key Endpoint

The current backend mounts:

```text
GET /.well-known/qr-public-key
```

Clients should use this endpoint to refresh the public key when online.

## Production Validation

When `ENVIRONMENT=production`, startup fails if neither valid key files nor valid base64 PEM values are available. Production also validates strong JWT and mesh-secret configuration.

## Rotation

The current QR service loads one active key pair.

1. Generate a replacement pair.
2. Update key files or base64 env vars.
3. Restart the API process.
4. Confirm `/.well-known/qr-public-key` serves the new public key.
5. Roll mobile/dashboard verification caches forward on next network contact.

Future zero-downtime rotation should add JWKS with `kid` support. Until then, coordinate restarts carefully because old QR JWTs may require the previous public key for verification.
