# SafeRoute Dashboard

Last reviewed: 2026-05-16

The dashboard is the React/Vite authority command center. It is no longer the default Vite template; it now provides authenticated operational views for SafeRoute authorities.

## Stack

- React 19
- TypeScript
- Vite
- React Router
- Axios
- Leaflet / React Leaflet
- lucide-react icons
- qrcode for offline onboarding QR display

## Run Locally

```powershell
cd dashboard
npm install
npm run dev
```

The dev server usually runs at `http://localhost:5173`.

Set the backend URL with:

```powershell
$env:VITE_API_BASE_URL="http://localhost:8000"
npm run dev
```

If not set, `dashboard/src/api.ts` defaults to `http://localhost:8000`.

## Build

```powershell
npm run build
npm run preview
```

## Current Pages

| Route | Page | Backend dependencies |
| --- | --- | --- |
| `/login` | Authority login | `POST /auth/login/authority` |
| `/` | Command overview | `GET /dashboard/analytics`, `GET /dashboard/locations`, `GET /sos/events` |
| `/zones` | Zone operations | `GET /destinations`, `GET /zones`, `POST /zones`, `PUT /zones/{id}`, `DELETE /zones/{id}`, `GET /onboard/preview/{destination_id}` |
| `/sos` | SOS triage board | `GET /sos/events`, `GET /sos/events/{id}/delivery`, `POST /sos/events/{id}/acknowledge`, `POST /sos/events/{id}/respond` |

## Permissions

Dashboard permissions are resolved in `src/auth.ts`.

Built-in `authority` and `superadmin` roles receive:

- `overview:view`
- `zones:view`
- `zones:manage`
- `sos:view`
- `sos:respond`
- `map:view`

Inactive, suspended, or unrecognized accounts are denied dashboard access.

## Operational Notes

- API calls attach `Authorization: Bearer <token>` from local storage.
- A `401` response clears local session data and redirects to `/login`.
- Dashboard data auto-refreshes every 10 seconds via `POLL_INTERVAL_MS`.
- The overview map displays locations and incidents; stale location threshold currently comes from `/dashboard/analytics`.
- Zone management supports circle and polygon zones and protects mutating actions behind `zones:manage`.
- SOS triage separates active incidents from resolved/expired records and can expand the audited delivery timeline.
