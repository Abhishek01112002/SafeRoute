# SafeRoute Mesh Secret Lifecycle

## Purpose
`mesh_secret` signs offline SOS packets before the phone has network access. It is separate from JWTs, TUIDs, and global salts. JWTs authenticate API requests; mesh secrets authenticate offline SOS origin.

## Issuance
- The backend derives a random-looking versioned mesh secret on tourist registration and login.
- Responses include:
  - `mesh_secret`
  - `mesh_key_version`
  - `mesh_key_expires_at` when configured
- Mobile stores these fields in secure storage.
- Mesh secrets are never printed in logs and are never stored in shared preferences.

## Server Storage
Production uses derivation metadata rather than raw secret storage:

```text
mesh_secret = HMAC-SHA256(MESH_SECRET_MASTER_KEY, "{tourist_id}:{tuid}:{key_version}")
```

The database stores tourist id, key version, status, creation time, optional revocation time, and grace-window expiry. `MESH_SECRET_MASTER_KEY` is required in production.

## Rotation
- `POST /v3/tourist/mesh-key/rotate` creates the next key version for the authenticated tourist.
- The newest key is returned to the mobile app and becomes the signing key.
- Older keys remain valid for a grace window so SOS packets created offline can still be verified after connectivity returns.
- Revoked keys are rejected immediately.

## Verification
The relay endpoint reconstructs the CBEP canonical payload and validates the truncated HMAC against every active or grace-valid key matching the submitted TUID suffix and key version. Unknown suffixes, stale timestamps, revoked keys, and invalid HMACs are rejected without queueing an SOS.

