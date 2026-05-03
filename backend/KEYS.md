# SafeRoute RS256 Key Management

SafeRoute Digital Identity (v3.0) uses **RS256** asymmetric cryptography to sign QR codes.
This allows the backend to sign QRs (using the private key), and mobile devices to verify them offline (using the public key).

## Key Generation

To generate the required keys for production:

1. Enter the `backend/` directory.
2. Run the key generator script:
   ```bash
   python generate_keys.py
   ```
3. This creates two files:
   - `private_key.pem` (KEEP SECRET! Never commit this)
   - `public_key.pem` (Safe to distribute)

## Configuration

In your `.env` file, ensure the paths point to the generated keys:

```env
PRIVATE_KEY_PATH=./private_key.pem
PUBLIC_KEY_PATH=./public_key.pem
```

## Key Rotation Strategy

The `QRService` currently supports loading a single key pair on startup.

**To rotate keys:**
1. Generate a new pair: `python generate_keys.py` (rename the old ones as backups).
2. Restart the API container. The backend will immediately start issuing new QRs using the new private key.
3. The new public key is automatically served at `/.well-known/qr-public-key`.
4. Mobile apps will download the new public key when they next connect to the internet.

*Note: In the future, to support zero-downtime rotation, we will expose a JWKS endpoint (`/.well-known/jwks.json`) supporting multiple key IDs (`kid`). For now, replacing the files and restarting is sufficient for the MVP phase.*
