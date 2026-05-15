# SafeRoute CBEP v3 SOS Packet Spec

Last reviewed: 2026-05-16

Current backend endpoint: `POST /sos/trigger/relay`.

## Purpose
CBEP v3 is the compact BLE advertisement format used for offline SOS relay. It is designed for opportunistic broadcast, not paired transfer. Any SafeRoute device can relay the packet, but only the origin tourist's mesh secret can sign it.

## 31-Byte SOS Advertisement
This is the full CBEP v3 payload used when the phone supports extended BLE advertising. Some Android devices cannot advertise a 31-byte manufacturer payload in legacy mode, so mobile clients must support the 24-byte fallback below.
All integer fields are big-endian.

| Bytes | Field | Notes |
| --- | --- | --- |
| 0 | version/hop | high nibble = protocol version `3`, low nibble = remaining hop count |
| 1 | packet type | `1` = SOS alert |
| 2 | key version | tourist mesh key version used for HMAC |
| 3 | flags | reserved, send `0` in V1 |
| 4-9 | idempotency hash | first 6 bytes of SHA-256(idempotency_key) |
| 10-13 | TUID suffix | last 4 ASCII chars of the origin tourist TUID |
| 14-17 | latitude | signed int32, degrees scaled by 1e6 |
| 18-21 | longitude | signed int32, degrees scaled by 1e6 |
| 22-25 | unix minute | UTC epoch seconds divided by 60 |
| 26-29 | origin HMAC | first 4 bytes of HMAC-SHA256(canonical payload) |
| 30 | checksum | sum of bytes 0-29 modulo 256 |

## 24-Byte Legacy Fallback Advertisement
This format fits inside legacy Android manufacturer advertising data. It is used only when full extended advertising fails.

| Bytes | Field | Notes |
| --- | --- | --- |
| 0 | version/hop | high nibble = protocol version `3`, low nibble = remaining hop count |
| 1 | packet type | `1` = SOS alert |
| 2 | key version | tourist mesh key version used for HMAC |
| 3-8 | idempotency hash | first 6 bytes of SHA-256(idempotency_key) |
| 9-12 | TUID suffix | last 4 ASCII chars of the origin tourist TUID |
| 13-15 | latitude | signed int24, degrees scaled by 1e4 |
| 16-18 | longitude | signed int24, degrees scaled by 1e4 |
| 19-20 | unix-minute modulo | unix minute modulo 65536; receiver expands to nearest current epoch window |
| 21-23 | origin HMAC | first 3 bytes of HMAC-SHA256(canonical payload) |

Legacy fallback coordinates are intentionally quantized to 4 decimal places before signing. This keeps the packet small while preserving roughly 11-meter position precision.

## Canonical Payload
The HMAC input is:

```text
v1:{idempotency_hash_hex}:{tuid_suffix}:{lat_6}:{lng_6}:{unix_minute}:{trigger_type}
```

For the current mobile relay flow, `trigger_type` is normally `MANUAL`, but the backend accepts the same enum as direct SOS: `MANUAL`, `AUTO_FALL`, or `GEOFENCE_BREACH`. `lat_6` and `lng_6` are decimal degree strings with exactly six fractional digits. Mutable relay fields such as hop count are excluded from the signature so relayers can decrement hop count without invalidating origin authenticity.

## Relay Rules
- A relayer may decrement hop count and rebroadcast the packet.
- A relayer must not replace the origin TUID suffix, timestamp, idempotency hash, coordinates, key version, or HMAC.
- When a relayer reaches the backend, it submits the decoded packet to `POST /sos/trigger/relay`.
- The backend records relayer identity separately when authenticated, but the SOS incident belongs to the origin tourist only.

## Replay Window
The backend accepts packets whose unix-minute timestamp is not more than 10 minutes in the future and not older than `SOS_DELIVERY_TTL_SECONDS` seconds. The current default TTL is 7200 seconds. Accepted relay packets are deduplicated through a compact key in the form `BLE-{origin_tuid_suffix}-{idempotency_hash}-{unix_minute}` against the origin tourist.

## Backend Validation Summary

- `origin_tuid_suffix` must be 4 characters.
- `idempotency_hash` must be at least 12 hex characters.
- Coordinates must be valid latitude/longitude.
- `key_version` must match an active or grace-valid mesh key for the suffix.
- `origin_signature` is verified against the canonical payload using the derived mesh secret.
- Unknown suffixes, stale timestamps, revoked keys, and invalid HMACs are rejected without queueing an SOS.
