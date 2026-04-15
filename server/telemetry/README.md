# YueLink Telemetry Server

Drop-in FastAPI module that lives alongside the existing `checkin-api`
service on `23.80.91.14`. Handles:

- **Ingest** — accepts the same POST body the client already sends to
  `https://yue.yuebao.website/api/client/telemetry`.
- **Storage** — SQLite at `/var/lib/yuelink-telemetry/events.db`.
- **Stats** — REST endpoints + an HTML dashboard (Basic Auth).

## Files

- `telemetry.py` — FastAPI `APIRouter`. Include it in the existing app.
- `dashboard.html` — single-page dashboard served at
  `/api/client/telemetry/dashboard`.

## Deploy

```bash
# 1. Copy files to server
scp server/telemetry/telemetry.py root@23.80.91.14:/opt/checkin-api/telemetry.py
scp server/telemetry/dashboard.html root@23.80.91.14:/opt/checkin-api/dashboard.html

# 2. Wire into the existing FastAPI app in /opt/checkin-api/main.py. Add
#    these two lines near the top-level `app = FastAPI(...)` block:
#
#        from telemetry import router as telemetry_router
#        app.include_router(telemetry_router)
#
#    If the existing main.py already has a POST /api/client/telemetry
#    handler, remove it — telemetry.py replaces it.

# 3. Set dashboard credentials (required — dashboard fails closed if unset)
ssh root@23.80.91.14 "systemctl edit --full checkin-api"
# Add under [Service]:
#   Environment=TELEMETRY_DASHBOARD_USER=yuelink
#   Environment=TELEMETRY_DASHBOARD_PASSWORD=<generate with: openssl rand -hex 16>

# 4. Create SQLite dir + restart
ssh root@23.80.91.14 "mkdir -p /var/lib/yuelink-telemetry && \
    chown checkin-api:checkin-api /var/lib/yuelink-telemetry && \
    systemctl restart checkin-api"
```

## Endpoints

| Route | Auth | Purpose |
|---|---|---|
| `POST /api/client/telemetry` | none | Ingest (what the client sends) |
| `GET  /api/client/telemetry/stats/summary?days=7` | basic | Top events + totals |
| `GET  /api/client/telemetry/stats/dau?days=30` | basic | Daily active clients |
| `GET  /api/client/telemetry/stats/startup_funnel?days=7` | basic | `startup_ok` vs `startup_fail` by step |
| `GET  /api/client/telemetry/stats/errors?days=7` | basic | Top crash types |
| `GET  /api/client/telemetry/stats/versions?days=7` | basic | Platform × version client counts |
| `GET  /api/client/telemetry/dashboard` | basic | HTML dashboard |

Open `https://yue.yuebao.website/api/client/telemetry/dashboard` in a
browser. It refreshes automatically every minute.

## Config

Environment variables:

- `TELEMETRY_DB_PATH` — default `/var/lib/yuelink-telemetry/events.db`
- `TELEMETRY_RETENTION_DAYS` — default `90`. Events older than this are
  pruned on a 1/1000 sampled basis.
- `TELEMETRY_DASHBOARD_USER` / `TELEMETRY_DASHBOARD_PASSWORD` — required
  for stats/dashboard. Stats endpoints return 503 if unset.

## Privacy

The ingest handler:

- Hard-caps event count to 200 per request.
- Rejects event names > 64 chars.
- Truncates every string prop to 120 chars.
- Only persists simple scalars (`str`/`int`/`float`/`bool`/`null`);
  nested objects/arrays are silently dropped.
- Never logs request bodies — only parsed rows.

The client (`lib/shared/telemetry.dart`) is opt-in (OFF by default) and
sends an anonymous per-install UUID as `client_id`. No email, token,
subscription URL, or node information is ever sent.
