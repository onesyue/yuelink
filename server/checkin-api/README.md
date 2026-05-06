# checkin-api — YueLink Checkin + Telemetry FastAPI service

Single FastAPI process running on `23.80.91.14:8011`, fronted by
nginx (which is on `66.55.76.208`) at
`https://yue.yuebao.website/api/client/`. The service handles four
unrelated-but-co-resident concerns:

1. **Checkin** — `POST /api/client/checkin` and friends (the original
   reason for this service).
2. **Telemetry ingest + dashboard** — `/api/client/telemetry`,
   `/api/client/telemetry/dashboard`, `/api/client/telemetry/flags`.
3. **DNS scheduler / SRE side** — `/api/sre/...` for the active-probe
   runner and the human-review queue (see `server/telemetry/ROADMAP.md`).
4. **Web gateway** — generic auth-relay against XBoard's Sanctum tokens.

The Python source for #2 lives one directory over at
`server/telemetry/` (telemetry.py / dashboard.html / migrate /
test_*). Reasons for the split:

- `server/telemetry/` was added first in an earlier sprint and has
  its own ROADMAP / unit tests in tree.
- `server/checkin-api/` was added 2026-05-06 to bring the entry-point
  files (main.py / web_gateway.py / nodes-inventory-path-map.json /
  requirements.txt / migrate_sqlite_to_pg.py) into git so the
  hand-deployed gap closes.

Both directories are physically merged into `/opt/checkin-api/` on
the deployment host. **When deploying or restoring the service, scp
the union of the two directories.** See "Deploy" below.

## File inventory

| Path in repo | Path on server | Purpose |
|---|---|---|
| `server/checkin-api/main.py` | `/opt/checkin-api/main.py` | FastAPI entry-point. Imports telemetry as a sibling module. Owns checkin endpoints, web_gateway routing, telemetry ingest enrichment (`_telemetry_client_context`, `_CN_CARRIER_ASN`), path-class derivation (`_telemetry_path_class_for_xb_server_id`). |
| `server/checkin-api/web_gateway.py` | `/opt/checkin-api/web_gateway.py` | XBoard Sanctum auth proxy. |
| `server/checkin-api/migrate_sqlite_to_pg.py` | `/opt/checkin-api/migrate_sqlite_to_pg.py` | One-shot history migration; kept for record. |
| `server/checkin-api/nodes-inventory-path-map.json` | `/opt/checkin-api/nodes-inventory-path-map.json` | XBoard `v2_server.id` → `path_class` (`direct` / `via_v4_relay` / `via_v6_relay`) mapping. Refreshed manually when the v4 / v6 relay topology changes. |
| `server/checkin-api/requirements.txt` | `/opt/checkin-api/requirements.txt` | uvicorn / fastapi / psycopg2 etc. |
| `server/telemetry/telemetry.py` | `/opt/checkin-api/telemetry.py` | Telemetry ingest + aggregation + dashboard router. `from telemetry import router_dashboard` in main.py. |
| `server/telemetry/dashboard.html` | `/opt/checkin-api/dashboard.html` | Dashboard front-end (vanilla JS + tab system). |
| `server/telemetry/test_stats_nodes_aggregation.py` | not deployed | Unit tests, run locally. |
| `server/telemetry/test_node_state.py` | not deployed | Unit tests, run locally. |

## Deploy / restore on a fresh host

```bash
# On 23.80.91.14 (or replacement host)

# 1. System-level prerequisites
apt-get install -y python3 python3-venv

# 2. Create the directory and copy the union of both repo directories
sudo mkdir -p /opt/checkin-api
sudo scp -r yuelink-repo/server/checkin-api/*.py        /opt/checkin-api/
sudo scp    yuelink-repo/server/checkin-api/*.json      /opt/checkin-api/
sudo scp    yuelink-repo/server/checkin-api/requirements.txt /opt/checkin-api/
sudo scp    yuelink-repo/server/telemetry/telemetry.py  /opt/checkin-api/
sudo scp    yuelink-repo/server/telemetry/dashboard.html /opt/checkin-api/

# 3. venv + deps
cd /opt/checkin-api
python3 -m venv venv
venv/bin/pip install -r requirements.txt

# 4. Systemd unit (/etc/systemd/system/checkin-api.service)
#    Required env vars (the live host's are listed below — fill in your own):
#      TELEMETRY_DASHBOARD_USER=yuelink
#      TELEMETRY_DASHBOARD_PASSWORD=<dashboard basic-auth password>
#      TELEMETRY_DATABASE_DSN=host=66.55.76.208 port=5432 user=root password=<...> dbname=yueops
#      TELEMETRY_SCHEMA=telemetry
#      TELEMETRY_ID_SALT=yuelink-anonymous-telemetry-v1
#    ExecStart=/opt/checkin-api/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8011 --workers 1
#    WorkingDirectory=/opt/checkin-api

systemctl daemon-reload
systemctl enable --now checkin-api

# 5. nginx-side: see server/nginx/ for the matching config (proxy_pass to 127.0.0.1:8011).
```

## Idempotency markers

`main.py` and `telemetry.py` carry comment sentinels so future
re-deploys / patches are idempotent. Search before patching:

| Marker | Block | Owner |
|---|---|---|
| `# yuelink:cymru-v6+carrier` | `_telemetry_client_context` v6 path + `_CN_CARRIER_ASN` map | added 2026-05-06 |
| `# yuelink:cymru-retry-no-failure-cache` | retry loop + skip-cache-on-failure inside the same function | added 2026-05-06 |

If a patch script can't locate its marker → either the file is from
**before** the patch (apply normally) or **already patched** (skip).
Never blind-edit if the marker is missing without checking.

## Database / external dependencies

| Resource | Host | Notes |
|---|---|---|
| Telemetry tables | `66.55.76.208:5432` db `yueops`, schema `telemetry` | written by `_telemetry_store_batch` |
| XBoard auth (read-through) | `http://66.55.76.208:8001/api/v1/user/info` | direct (NOT CloudFront — UA-blocked) |
| Cymru ASN reverse | `*.origin.asn.cymru.com` (v4) and `*.origin6.asn.cymru.com` (v6) | dig over recursive DNS, 2-attempt retry |

## Logs

```
journalctl -u checkin-api --since "1 hour ago"   # uvicorn access + telemetry ingest log lines
```

Telemetry ingest log line example (look for batch-level summary):

```
[TELEMETRY] batch asn=4134 cc=CN count=12 stored=12 node_stored=8 events={…} versions={…}
```
