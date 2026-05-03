# docs/monitoring.md
#
# SafeRoute — Health Check & Monitoring Guide
# =============================================

## Health Check Endpoint

The backend exposes a health check endpoint at:

```
GET /health
```

**Response (200 OK)**:
```json
{
  "status": "ok",
  "db": "connected",
  "version": "3.0.0"
}
```

This endpoint requires **no authentication** and is safe to poll frequently.

---

## Setting Up UptimeRobot (Free — Recommended)

[UptimeRobot](https://uptimerobot.com) monitors your endpoint every 5 minutes
and alerts you via email/SMS if it goes down.

### Setup Steps

1. Create a free account at [uptimerobot.com](https://uptimerobot.com)
2. Click **"Add New Monitor"**
3. Configure:
   - **Monitor Type**: HTTP(S)
   - **Friendly Name**: `SafeRoute Production API`
   - **URL**: `https://api.saferoute.app/health`
   - **Monitoring Interval**: Every 5 minutes
   - **Alert Contacts**: Add your email + phone
4. Under **"Advanced Settings"**:
   - **Keyword**: `"ok"` (alert if this keyword is NOT in response)
5. Click **"Create Monitor"**

You'll receive an email/SMS within 5 minutes if the API goes down.

---

## What to Monitor

| Endpoint | Check | Alert Condition |
|---|---|---|
| `GET /health` | HTTP 200 + `{"status":"ok"}` | Any non-200 or `status != "ok"` |
| `GET /health` | Response time < 3000ms | Latency > 3s consistently |

---

## Local Health Check (Development)

```bash
# Quick check when backend is running:
curl http://localhost:8000/health

# Expected response:
# {"status":"ok","db":"connected","version":"3.0.0"}
```

---

## Incident Response

If UptimeRobot alerts you:

1. **Check backend logs**: `make logs`
2. **Check DB connection**: `alembic current`
3. **Restart if needed**: `make restart`
4. **Check disk space** (SQLite can fail if disk is full): `df -h`
5. **Post-incident**: Create a GitHub issue tagged `incident` with root cause

---

## Future: Structured Uptime Dashboard

Consider adding [Statuspage.io](https://www.atlassian.com/software/statuspage)
for a public status page that tourists/authorities can check.
