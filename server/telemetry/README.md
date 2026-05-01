# YueLink Telemetry Server

FastAPI module mounted inside the existing `checkin-api` service on
`23.80.91.14`. Handles ingest, feature flags, NPS, per-node stats, and
a single-page dashboard.

**Storage**: PostgreSQL 16 on the shared yueops cluster
(`66.55.76.208:5432/yueops`, schema `telemetry`). Same DB yueops uses —
cross-schema joins against `server_nodes` / `v2_server` are O(index)
instead of cross-process, which Phase-2 of the
[ROADMAP](./ROADMAP.md) depends on.

Previous sqlite build (`/var/lib/yuelink-telemetry/events.db`) has
been migrated and archived; see `migrate_sqlite_to_pg.py`.

## Files

- `telemetry.py` — FastAPI `APIRouter`. Schema auto-created on first import.
- `dashboard.html` — single-page dashboard served at `/api/client/telemetry/dashboard`.
- `migrate_sqlite_to_pg.py` — one-shot migration (already run on 2026-04-15).

## Deploy

```bash
# 1. Copy files
scp server/telemetry/telemetry.py        root@23.80.91.14:/opt/checkin-api/
scp server/telemetry/dashboard.html      root@23.80.91.14:/opt/checkin-api/
scp server/telemetry/migrate_sqlite_to_pg.py root@23.80.91.14:/opt/checkin-api/

# 2. Wire into /opt/checkin-api/main.py near the `app = FastAPI(...)` block:
#       from telemetry import router as telemetry_router
#       app.include_router(telemetry_router)
#    (If main.py already has an inline POST /api/client/telemetry
#    handler, remove it — telemetry.py replaces it.)

# 3. Set env vars in systemctl drop-in. IMPORTANT: the DSN contains
#    spaces, so the systemd Environment= line MUST be quoted, otherwise
#    systemd splits on whitespace and libpq sees a half-DSN and prompts
#    for a password.
ssh root@23.80.91.14 'cat > /etc/systemd/system/checkin-api.service.d/telemetry-env.conf <<EOF
[Service]
Environment=TELEMETRY_DASHBOARD_USER=yuelink
Environment=TELEMETRY_DASHBOARD_PASSWORD=<openssl rand -hex 16>
Environment="TELEMETRY_DATABASE_DSN=host=<pg-host> port=5432 user=<pg-user> password=<pg-password> dbname=<pg-db>"
Environment=TELEMETRY_SCHEMA=telemetry
EOF'

ssh root@23.80.91.14 'systemctl daemon-reload && systemctl restart checkin-api'

# 4. (first deploy only) Migrate from sqlite
ssh root@23.80.91.14 'cd /opt/checkin-api && venv/bin/python migrate_sqlite_to_pg.py'
ssh root@23.80.91.14 'mv /var/lib/yuelink-telemetry/events.db /var/lib/yuelink-telemetry/events.db.presync.$(date +%Y%m%d)'
```

## Endpoints

| Route | Auth | Purpose |
|---|---|---|
| `POST /api/client/telemetry` | none | Ingest (what the client sends) |
| `GET  /api/client/telemetry/flags` | none | Evaluated flags for client_id |
| `POST /api/client/telemetry/nps` | none | NPS score submission |
| `GET  /api/client/telemetry/stats/summary?days=7` | basic | Top events + totals |
| `GET  /api/client/telemetry/stats/dau?days=30` | basic | Daily active clients |
| `GET  /api/client/telemetry/stats/crash_free?days=7` | basic | Crash-free session rate |
| `GET  /api/client/telemetry/stats/startup_funnel?days=7` | basic | 8-step funnel, ok vs fail |
| `GET  /api/client/telemetry/stats/errors?days=7` | basic | Top crash types |
| `GET  /api/client/telemetry/stats/versions?days=7` | basic | Platform × version clients |
| `GET  /api/client/telemetry/stats/nodes?days=7` | basic | Per-fp health scores |
| `GET  /api/client/telemetry/stats/nps?days=30` | basic | NPS aggregate + comments |
| `GET  /api/client/telemetry/admin/flags` | basic | List all flags |
| `POST /api/client/telemetry/admin/flags` | basic | Set a flag value / rollout_pct |
| `GET  /api/client/telemetry/dashboard` | basic | HTML dashboard |

## Config (env vars)

| Var | Default |
|---|---|
| `TELEMETRY_DATABASE_DSN` | *(required; libpq DSN, injected by systemd/secret manager)* |
| `TELEMETRY_SCHEMA` | `telemetry` |
| `TELEMETRY_RETENTION_DAYS` | `90` (sampled prune, 1/1000 requests) |
| `TELEMETRY_DASHBOARD_USER` | *(required for stats/admin)* |
| `TELEMETRY_DASHBOARD_PASSWORD` | *(required for stats/admin)* |

Stats endpoints fail closed (503) if the dashboard creds aren't set.

## Privacy

Ingest hard-caps:
- ≤200 events per POST
- event name ≤64 chars
- every string prop truncated to 200 chars
- nested objects / arrays: only simple scalar leaves survive
- node event payloads: fingerprint-only (sha1-16 over type+server+port+protocol-extras).
  Server IP / port / SNI / WS path / pubkey never leave the device in plain text.
- request bodies are never logged

Client (`lib/shared/telemetry.dart`) is opt-in (OFF by default), sends
an anonymous per-install UUID as `client_id`, and offers Settings →
Privacy → "View sent events" so users can see exactly what has been
recorded.

## Schema summary (PG)

```
telemetry.events(id, ts, server_ts, day, event, client_id, session_id,
                 platform, version, props JSONB)
   indexes: day, event, client_id, session_id, (day,event), GIN(props)

telemetry.node_events(id, ts, day, client_id, platform, version, event,
                      fp, type, region, delay_ms INT, ok SMALLINT,
                      reason, group_name)
   indexes: (fp,day), day, event

telemetry.node_identity(identity_id, current_fp UNIQUE, label, protocol,
                        region, sid, xb_server_id, first_seen, last_seen,
                        retired_at)

telemetry.node_fp_history(fp PK, identity_id FK, bound_at, retired_at)

telemetry.feature_flags(key PK, value_json, rollout_pct, updated_at)

telemetry.nps_responses(id, ts, day, client_id, platform, version,
                        score SMALLINT, comment)
```
