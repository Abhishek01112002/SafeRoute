# SafeRoute Monitoring Guide

Last reviewed: 2026-05-16

This guide matches the current `backend/app/routes/health.py` implementation.

## Health Endpoints

| Endpoint | Auth | Purpose | Failure behavior |
| --- | --- | --- | --- |
| `GET /health` | None | Basic process health and legacy cache counts | Returns `200` if the app can serve requests |
| `GET /live` | None | Liveness probe | Returns `{"status":"alive"}` |
| `GET /ready` | None | Readiness probe for DB, Redis, and MinIO | Returns `503` only when DB check fails |
| `GET /metrics` | None | Prometheus-style text metrics from in-memory counters | Returns text lines such as `saferoute_request_count 0` |
| `POST /cleanup` | None | Manual location-ping retention cleanup | Deletes old location pings according to `RETENTION_DAYS_LOCATION` |

## Example Responses

`GET /health`

```json
{
  "status": "ok",
  "timestamp": "2026-05-16T12:00:00.000000Z",
  "tourists": 0,
  "authorities": 0
}
```

`GET /ready`

```json
{
  "status": "ready",
  "checks": {
    "db": true,
    "redis": false,
    "minio": false
  },
  "timestamp": "2026-05-16T06:30:00+00:00"
}
```

Redis and MinIO are soft dependencies. A response can still be ready when those checks are false. The database is the hard dependency.

## Local Checks

```powershell
curl http://localhost:8000/health
curl http://localhost:8000/live
curl http://localhost:8000/ready
curl http://localhost:8000/metrics
```

## Suggested External Monitoring

Use any HTTP monitor against:

- `https://<api-host>/live` for process uptime.
- `https://<api-host>/ready` for deploy/load-balancer readiness.
- `https://<api-host>/health` for basic public availability.

Alert on:

- non-2xx from `/live`,
- non-2xx from `/ready`,
- repeated latency above 3 seconds,
- rising `saferoute_error_count`,
- stale SOS queue processing or no audit writes for active incidents.

## SOS-Specific Observability

For life-critical incidents, inspect:

- `GET /sos/events`
- `GET /sos/events/{event_id}/delivery`
- `sos_dispatch_queue`
- `sos_delivery_audit`
- `sos_provider_circuit`

Queue states include `PENDING`, `DISPATCHING`, `DELIVERED`, `ESCALATED`, `EXPIRED_NO_DELIVERY`, `EXPIRED_NO_RESPONSE`, and `CANCELLED`.

## Incident Response

1. Check `/ready` to confirm database availability.
2. Check backend logs for `sos.worker.tick_failed`, provider failures, or startup validation errors.
3. Inspect the SOS delivery audit endpoint for affected incidents.
4. Confirm webhook/Twilio/Firebase configuration if delivery is skipped.
5. Restart the app only after capturing logs and queue state.
6. Create an incident issue with timeline, root cause, user impact, and follow-up actions.
