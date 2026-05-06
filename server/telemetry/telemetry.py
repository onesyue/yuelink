"""
YueLink telemetry — ingest + stats + feature flags + NPS + dashboard.

Drop-in FastAPI APIRouter mounted alongside the existing checkin-api
service on 23.80.91.14.

Storage: **PostgreSQL 16** on the shared yueops database
(schema `telemetry`). The `TELEMETRY_DATABASE_DSN` env var is a standard
libpq DSN and is required in production; this module deliberately has no
credential-bearing default.
Tables live in the `telemetry` schema so they don't collide with yueops'
own models.

Why PG instead of the earlier sqlite build:
- MVCC: concurrent writers don't block each other while prune runs.
- GIN indexes on JSONB props: O(log n) instead of table-scan json_extract.
- Same cluster yueops already uses → zero extra ops surface.
- Quality-plane bridge (see ROADMAP.md) needs to JOIN node_events with
  yueops.server_nodes — same-DB joins are O(index) instead of cross-process.

Routes (all under /api/client/telemetry):

    POST /                         ingest a batch (what the app sends)
    GET  /flags                    feature flag evaluation for a client_id
    POST /nps                      NPS score + comment submission
    GET  /stats/summary            top events + counts               (BasicAuth)
    GET  /stats/dau                daily active clients              (BasicAuth)
    GET  /stats/crash_free         crash-free session rate           (BasicAuth)
    GET  /stats/startup_funnel     8-step funnel ok vs fail          (BasicAuth)
    GET  /stats/connection_health  connect/repair failure signals    (BasicAuth)
    GET  /stats/errors             top error types                   (BasicAuth)
    GET  /stats/versions           platform × version                (BasicAuth)
    GET  /stats/nodes              node fingerprint health scores    (BasicAuth)
    GET  /stats/nps                NPS aggregate + last comments     (BasicAuth)
    GET  /admin/flags              admin JSON view of current flags  (BasicAuth)
    POST /admin/flags              write a flag value                (BasicAuth)
    GET  /dashboard                single-page HTML dashboard        (BasicAuth)
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Iterator, Optional

import psycopg2
import psycopg2.extras
import psycopg2.pool
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

# ── Configuration ───────────────────────────────────────────────────────

DSN = os.environ.get("TELEMETRY_DATABASE_DSN", "")
SCHEMA = os.environ.get("TELEMETRY_SCHEMA", "telemetry")

DASHBOARD_USER = os.environ.get("TELEMETRY_DASHBOARD_USER", "")
DASHBOARD_PASSWORD = os.environ.get("TELEMETRY_DASHBOARD_PASSWORD", "")
RETENTION_DAYS = int(os.environ.get("TELEMETRY_RETENTION_DAYS", "90"))

# SRE-tier APIs (P7 node state, P5 active probe). Separated from the
# dashboard credential so a leaked dashboard cookie can't quarantine
# nodes or write fake probe results. SRE_TOKEN is a bearer token; the
# active probe runner uses ACTIVE_PROBE_TOKEN, which can be the same in
# small deployments but separated by default so we can rotate runner
# tokens without disturbing reviewers.
SRE_TOKEN = os.environ.get("TELEMETRY_SRE_TOKEN", "")
ACTIVE_PROBE_TOKEN = os.environ.get(
    "TELEMETRY_ACTIVE_PROBE_TOKEN", SRE_TOKEN
)
ACTIVE_PROBE_RATE_LIMIT_PER_MIN = int(
    os.environ.get("TELEMETRY_ACTIVE_PROBE_RATE_LIMIT", "120")
)
MAX_PROBE_RESULTS_PER_REQUEST = 500

MAX_EVENTS_PER_REQUEST = 200
MAX_EVENT_NAME_LEN = 64
MAX_PROP_VALUE_LEN = 200
MAX_INVENTORY_NODES = 200

router_ingest = APIRouter(prefix="/api/client/telemetry", tags=["telemetry"])
router_dashboard = APIRouter(prefix="/api/client/telemetry", tags=["telemetry"])
router_sre = APIRouter(prefix="/api/sre", tags=["telemetry-sre"])
router_active_probe = APIRouter(
    prefix="/api/sre/active-probe/v1", tags=["active-probe"]
)

# Backward-compatible default export for deployments that only want the
# read/admin surface. Existing checkin-api main.py owns ingest + flags.
router = router_dashboard
security = HTTPBasic()


def register(app):
    """Mount every YueLink telemetry router on a FastAPI app.

    Existing main.py deployments call `app.include_router(telemetry.router)`
    which only mounts the dashboard slice. Once main.py is updated to
    `telemetry.register(app)` it picks up ingest, dashboard, SRE, and the
    active-probe ingester in one place — no second deploy needed when
    new routers are added later.
    """
    app.include_router(router_ingest)
    app.include_router(router_dashboard)
    app.include_router(router_sre)
    app.include_router(router_active_probe)


# ── DB plumbing ─────────────────────────────────────────────────────────

_SCHEMA_SQL = f"""
CREATE SCHEMA IF NOT EXISTS {SCHEMA};
SET LOCAL search_path TO {SCHEMA}, public;

CREATE TABLE IF NOT EXISTS {SCHEMA}.events (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    server_ts   BIGINT NOT NULL,
    day         DATE NOT NULL,
    event       TEXT NOT NULL,
    client_id   TEXT,
    session_id  TEXT,
    platform    TEXT,
    version     TEXT,
    props       JSONB
);
CREATE INDEX IF NOT EXISTS idx_events_day       ON {SCHEMA}.events(day);
CREATE INDEX IF NOT EXISTS idx_events_event     ON {SCHEMA}.events(event);
CREATE INDEX IF NOT EXISTS idx_events_client    ON {SCHEMA}.events(client_id);
CREATE INDEX IF NOT EXISTS idx_events_session   ON {SCHEMA}.events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_day_event ON {SCHEMA}.events(day, event);
CREATE INDEX IF NOT EXISTS idx_events_props     ON {SCHEMA}.events USING GIN(props);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_events (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    day         DATE NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    event       TEXT NOT NULL,
    fp          TEXT,
    type        TEXT,
    region      TEXT,
    delay_ms    INTEGER,
    ok          SMALLINT,
    reason      TEXT,
    group_name  TEXT
);
CREATE INDEX IF NOT EXISTS idx_node_events_fp_day ON {SCHEMA}.node_events(fp, day);
CREATE INDEX IF NOT EXISTS idx_node_events_day    ON {SCHEMA}.node_events(day);
CREATE INDEX IF NOT EXISTS idx_node_events_event  ON {SCHEMA}.node_events(event);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_identity (
    identity_id  BIGSERIAL PRIMARY KEY,
    current_fp   TEXT UNIQUE,
    label        TEXT,
    protocol     TEXT,
    region       TEXT,
    sid          TEXT,
    xb_server_id INTEGER,
    first_seen   BIGINT NOT NULL,
    last_seen    BIGINT NOT NULL,
    retired_at   BIGINT
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_fp_history (
    fp          TEXT PRIMARY KEY,
    identity_id BIGINT NOT NULL REFERENCES {SCHEMA}.node_identity(identity_id),
    bound_at    BIGINT NOT NULL,
    retired_at  BIGINT
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.feature_flags (
    key         TEXT PRIMARY KEY,
    value_json  TEXT NOT NULL,
    rollout_pct INTEGER DEFAULT 100,
    updated_at  BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS {SCHEMA}.nps_responses (
    id          BIGSERIAL PRIMARY KEY,
    ts          BIGINT NOT NULL,
    day         DATE NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    score       SMALLINT NOT NULL,
    comment     TEXT
);
CREATE INDEX IF NOT EXISTS idx_nps_day ON {SCHEMA}.nps_responses(day);

-- P7 node state machine. Three tables:
--   node_state              — current label per node_fp (one row per node)
--   node_state_transitions  — append-only audit of every state change
--   node_state_reviews      — human review actions (approve / reject / hold)
--
-- The state machine intentionally has a `requires_human` flag rather than
-- letting code automatically `quarantined` a node. Only POST .../review
-- can move a node into `quarantined` — automation only proposes
-- `quarantine_candidate`. This is the gate that prevents a flapping RUM
-- signal from kicking 30% of the default group offline at 3am.
CREATE TABLE IF NOT EXISTS {SCHEMA}.node_state (
    node_fp                     TEXT PRIMARY KEY,
    current_state               TEXT NOT NULL,
    previous_state              TEXT,
    group_name                  TEXT,
    transport                   TEXT,
    last_seen_at                BIGINT NOT NULL,
    last_transition_at          BIGINT NOT NULL,
    reason                      TEXT,
    confidence                  REAL,
    rum_success_rate            REAL,
    active_probe_success_rate   REAL,
    ai_success_rate             REAL,
    reality_auth_failed_count   INTEGER NOT NULL DEFAULT 0,
    timeout_count               INTEGER NOT NULL DEFAULT 0,
    requires_human              BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at                  BIGINT NOT NULL,
    created_at                  BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_node_state_current
    ON {SCHEMA}.node_state(current_state);
CREATE INDEX IF NOT EXISTS idx_node_state_requires_human
    ON {SCHEMA}.node_state(requires_human) WHERE requires_human;
CREATE INDEX IF NOT EXISTS idx_node_state_last_transition
    ON {SCHEMA}.node_state(last_transition_at);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_state_transitions (
    id                 BIGSERIAL PRIMARY KEY,
    node_fp            TEXT NOT NULL,
    from_state         TEXT,
    to_state           TEXT NOT NULL,
    reason             TEXT,
    evidence_json      JSONB,
    triggered_by       TEXT NOT NULL,
    requires_human     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at         BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_node_state_transitions_fp
    ON {SCHEMA}.node_state_transitions(node_fp, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_node_state_transitions_triggered
    ON {SCHEMA}.node_state_transitions(triggered_by);

CREATE TABLE IF NOT EXISTS {SCHEMA}.node_state_reviews (
    id                 BIGSERIAL PRIMARY KEY,
    node_fp            TEXT NOT NULL,
    requested_state    TEXT NOT NULL,
    approved_state     TEXT,
    reviewer           TEXT NOT NULL,
    decision           TEXT NOT NULL,
    comment            TEXT,
    created_at         BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_node_state_reviews_fp
    ON {SCHEMA}.node_state_reviews(node_fp, created_at DESC);

-- P5 active probe. Independent of client RUM ingest so a flood of
-- probe results can't starve the user-facing pipeline. Probe runners
-- POST batches to /api/sre/active-probe/v1/results with a dedicated
-- token; their data lands here and is shown next to RUM in the dashboard.
CREATE TABLE IF NOT EXISTS {SCHEMA}.active_probe_runs (
    run_id             TEXT PRIMARY KEY,
    region             TEXT NOT NULL,
    probe_version      TEXT NOT NULL,
    started_at         BIGINT NOT NULL,
    finished_at        BIGINT,
    node_count         INTEGER,
    target_count       INTEGER,
    status             TEXT NOT NULL,
    error_summary_json JSONB
);
CREATE INDEX IF NOT EXISTS idx_active_probe_runs_region
    ON {SCHEMA}.active_probe_runs(region, started_at DESC);

CREATE TABLE IF NOT EXISTS {SCHEMA}.active_probe_results (
    id                 BIGSERIAL PRIMARY KEY,
    run_id             TEXT NOT NULL,
    node_fp            TEXT NOT NULL,
    group_name         TEXT,
    transport          TEXT,
    target             TEXT NOT NULL,
    status             TEXT NOT NULL,
    status_code        INTEGER,
    error_class        TEXT,
    latency_ms         INTEGER,
    timeout_ms         INTEGER,
    region             TEXT NOT NULL,
    probe_version      TEXT NOT NULL,
    sample_id          TEXT,
    exit_country       TEXT,
    exit_isp           TEXT,
    created_at         BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_active_probe_results_node
    ON {SCHEMA}.active_probe_results(node_fp, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_active_probe_results_target
    ON {SCHEMA}.active_probe_results(target, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_active_probe_results_run
    ON {SCHEMA}.active_probe_results(run_id);

CREATE TABLE IF NOT EXISTS {SCHEMA}.active_probe_dead_letter (
    id                 BIGSERIAL PRIMARY KEY,
    run_id             TEXT,
    reason             TEXT NOT NULL,
    payload_hash       TEXT,
    error_message      TEXT,
    created_at         BIGINT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_active_probe_dead_letter_created
    ON {SCHEMA}.active_probe_dead_letter(created_at DESC);
"""


_pool: Optional[psycopg2.pool.ThreadedConnectionPool] = None


def _get_pool() -> psycopg2.pool.ThreadedConnectionPool:
    global _pool
    if not DSN:
        raise RuntimeError("TELEMETRY_DATABASE_DSN is required")
    if _pool is None:
        _pool = psycopg2.pool.ThreadedConnectionPool(
            minconn=1,
            maxconn=10,
            dsn=DSN,
        )
    return _pool


def _ensure_schema() -> None:
    if not DSN:
        raise RuntimeError("TELEMETRY_DATABASE_DSN is required")
    conn = psycopg2.connect(DSN)
    try:
        conn.autocommit = True
        with conn.cursor() as cur:
            for stmt in _SCHEMA_SQL.strip().split(";\n"):
                stmt = stmt.strip()
                if stmt:
                    cur.execute(stmt)
    finally:
        conn.close()


try:
    _ensure_schema()
except Exception as e:  # pragma: no cover — startup-time, log and continue
    print(f"[telemetry] schema init failed: {e}")


@contextmanager
def db() -> Iterator[psycopg2.extensions.connection]:
    """Borrow a connection from the pool. Auto-commit on success, rollback on err."""
    pool = _get_pool()
    conn = pool.getconn()
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        pool.putconn(conn)


def _dict_cursor(conn):
    return conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)


def _maybe_prune() -> None:
    if secrets.randbelow(1000) != 0:
        return
    cutoff = (datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)).date()
    with db() as c, c.cursor() as cur:
        cur.execute(f"DELETE FROM {SCHEMA}.events WHERE day < %s", (cutoff,))
        cur.execute(f"DELETE FROM {SCHEMA}.node_events WHERE day < %s", (cutoff,))
        cur.execute(f"DELETE FROM {SCHEMA}.nps_responses WHERE day < %s", (cutoff,))


# ── Auth ────────────────────────────────────────────────────────────────


def require_dashboard_auth(
    credentials: HTTPBasicCredentials = Depends(security),
) -> str:
    if not DASHBOARD_USER or not DASHBOARD_PASSWORD:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Dashboard credentials not configured",
        )
    ok_u = secrets.compare_digest(credentials.username, DASHBOARD_USER)
    ok_p = secrets.compare_digest(credentials.password, DASHBOARD_PASSWORD)
    if not (ok_u and ok_p):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
            headers={"WWW-Authenticate": "Basic"},
        )
    return credentials.username


# ── Ingest ──────────────────────────────────────────────────────────────

_RESERVED_KEYS = {
    "event",
    "ts",
    "client_id",
    "session_id",
    "platform",
    "version",
    "seq",
}


def _is_simple_scalar(v) -> bool:
    return v is None or isinstance(v, (str, int, float, bool))


def _truncate_str(v: Optional[object], limit: int = MAX_PROP_VALUE_LEN) -> Optional[str]:
    if v is None:
        return None
    s = str(v)
    return s[:limit] if len(s) > limit else s


def _extract_node_rows(event_name: str, body: dict, day) -> list[tuple]:
    """Fan-out node_* events into flat node_events rows. Receives the RAW
    event dict so numeric/bool types are intact."""
    rows: list[tuple] = []
    ts_raw = body.get("ts")
    ts = int(ts_raw) if isinstance(ts_raw, (int, float)) else 0
    cid = _truncate_str(body.get("client_id"))
    platform = _truncate_str(body.get("platform"))
    version = _truncate_str(body.get("version"))

    def row(ev, fp, typ, region=None, delay_ms=None, ok=None, reason=None, group=None):
        return (
            ts, day, cid, platform, version, ev,
            _truncate_str(fp, 32),
            _truncate_str(typ, 24),
            _truncate_str(region, 16),
            int(delay_ms) if isinstance(delay_ms, (int, float)) else None,
            (1 if ok is True else (0 if ok is False else None)),
            _truncate_str(reason, 80),
            _truncate_str(group, 64),
        )

    if event_name == "node_inventory":
        nodes = body.get("nodes")
        if isinstance(nodes, list):
            for item in nodes[:MAX_INVENTORY_NODES]:
                if isinstance(item, dict):
                    rows.append(row(
                        "inventory_item",
                        item.get("fp"),
                        item.get("type"),
                        region=item.get("region"),
                    ))
    elif event_name == "node_urltest":
        rows.append(row(
            "urltest",
            body.get("fp"),
            body.get("type"),
            delay_ms=body.get("delay_ms"),
            ok=body.get("ok"),
        ))
    elif event_name == "node_connect":
        rows.append(row(
            "connect",
            body.get("fp"),
            body.get("type"),
            ok=body.get("ok"),
            reason=body.get("reason"),
            delay_ms=body.get("handshake_ms"),
        ))
    elif event_name == "node_select":
        rows.append(row(
            "select",
            body.get("fp"),
            body.get("type"),
            group=body.get("group"),
        ))
    return rows


@router_ingest.post("")
async def ingest(request: Request) -> JSONResponse:
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid json")
    events = body.get("events")
    if not isinstance(events, list):
        raise HTTPException(status_code=400, detail="events[] required")
    events = events[:MAX_EVENTS_PER_REQUEST]

    server_ts = int(time.time() * 1000)
    today = datetime.now(timezone.utc).date()

    event_rows: list[tuple] = []
    node_rows: list[tuple] = []

    for e in events:
        if not isinstance(e, dict):
            continue
        name = (e.get("event") or "").strip()
        if not name or len(name) > MAX_EVENT_NAME_LEN:
            continue
        ts = e.get("ts")
        if not isinstance(ts, (int, float)):
            ts = server_ts

        # Props stay JSON — Postgres JSONB preserves types, unlike our
        # earlier stringify-everything sqlite path.
        props: dict = {}
        for k, v in e.items():
            if k in _RESERVED_KEYS:
                continue
            if _is_simple_scalar(v):
                # Clamp string length, keep numeric/bool/null as-is.
                props[k] = _truncate_str(v) if isinstance(v, str) else v
            elif isinstance(v, list):
                cleaned = []
                for item in v[:MAX_INVENTORY_NODES]:
                    if isinstance(item, dict):
                        inner = {}
                        for ik, iv in item.items():
                            if not isinstance(ik, str):
                                continue
                            if _is_simple_scalar(iv):
                                inner[ik] = _truncate_str(iv) if isinstance(iv, str) else iv
                        if inner:
                            cleaned.append(inner)
                if cleaned:
                    props[k] = cleaned

        event_rows.append((
            int(ts),
            server_ts,
            today,
            name,
            _truncate_str(e.get("client_id")),
            _truncate_str(e.get("session_id")),
            _truncate_str(e.get("platform")),
            _truncate_str(e.get("version")),
            json.dumps(props, ensure_ascii=False) if props else None,
        ))

        if name.startswith("node_"):
            node_rows.extend(_extract_node_rows(name, e, today))

    if not event_rows:
        return JSONResponse({"ok": True, "count": 0})

    with db() as c, c.cursor() as cur:
        psycopg2.extras.execute_values(
            cur,
            f"INSERT INTO {SCHEMA}.events(ts, server_ts, day, event, client_id, "
            f"session_id, platform, version, props) VALUES %s",
            event_rows,
        )
        if node_rows:
            psycopg2.extras.execute_values(
                cur,
                f"INSERT INTO {SCHEMA}.node_events(ts, day, client_id, platform, version, "
                f"event, fp, type, region, delay_ms, ok, reason, group_name) VALUES %s",
                node_rows,
            )
            # node_identity upsert — region/protocol only update when incoming
            # value is non-null (urltest/connect rows carry no region).
            for r in node_rows:
                fp, typ, region = r[6], r[7], r[8]
                if not fp:
                    continue
                cur.execute(
                    f"""
                    INSERT INTO {SCHEMA}.node_identity(current_fp, protocol, region,
                                                       first_seen, last_seen)
                    VALUES (%s, %s, %s, %s, %s)
                    ON CONFLICT (current_fp) DO UPDATE SET
                      last_seen = EXCLUDED.last_seen,
                      protocol  = COALESCE(EXCLUDED.protocol, {SCHEMA}.node_identity.protocol),
                      region    = COALESCE(EXCLUDED.region,   {SCHEMA}.node_identity.region)
                    """,
                    (fp, typ, region, server_ts, server_ts),
                )

    _maybe_prune()
    return JSONResponse({"ok": True, "count": len(event_rows)})


# ── Feature flags ───────────────────────────────────────────────────────


@router_ingest.get("/flags")
def get_flags(client_id: str = "", platform: str = "", version: str = ""):
    """Return the effective flags for [client_id]."""
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(f"SELECT key, value_json, rollout_pct FROM {SCHEMA}.feature_flags")
        rows = cur.fetchall()
    out: dict[str, object] = {}
    for r in rows:
        pct = int(r["rollout_pct"] or 0)
        bucket = _bucket(client_id, r["key"])
        if bucket < pct:
            try:
                out[r["key"]] = json.loads(r["value_json"])
            except Exception:
                out[r["key"]] = r["value_json"]
    return {"flags": out}


def _bucket(client_id: str, key: str) -> int:
    h = hashlib.sha1(f"{key}|{client_id}".encode("utf-8")).digest()
    return h[0] % 100


@router_dashboard.get("/admin/flags")
def admin_list_flags(_user: str = Depends(require_dashboard_auth)):
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"SELECT key, value_json, rollout_pct, updated_at "
            f"FROM {SCHEMA}.feature_flags ORDER BY key"
        )
        return {"flags": cur.fetchall()}


@router_dashboard.post("/admin/flags")
async def admin_set_flag(
    request: Request,
    _user: str = Depends(require_dashboard_auth),
):
    body = await request.json()
    key = (body.get("key") or "").strip()
    if not key or len(key) > 64:
        raise HTTPException(status_code=400, detail="key required (≤64 chars)")
    value = body.get("value")
    rollout_pct = int(body.get("rollout_pct", 100))
    rollout_pct = max(0, min(100, rollout_pct))
    with db() as c, c.cursor() as cur:
        cur.execute(
            f"""
            INSERT INTO {SCHEMA}.feature_flags(key, value_json, rollout_pct, updated_at)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (key) DO UPDATE SET
              value_json = EXCLUDED.value_json,
              rollout_pct = EXCLUDED.rollout_pct,
              updated_at = EXCLUDED.updated_at
            """,
            (key, json.dumps(value), rollout_pct, int(time.time())),
        )
    return {"ok": True, "key": key}


# ── NPS ─────────────────────────────────────────────────────────────────


@router_dashboard.post("/nps")
async def nps_submit(request: Request) -> JSONResponse:
    body = await request.json()
    score = body.get("score")
    if not isinstance(score, (int, float)) or score < 0 or score > 10:
        raise HTTPException(status_code=400, detail="score must be 0-10")
    today = datetime.now(timezone.utc).date()
    with db() as c, c.cursor() as cur:
        cur.execute(
            f"""
            INSERT INTO {SCHEMA}.nps_responses(ts, day, client_id, platform, version,
                                               score, comment)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            """,
            (
                int(body.get("ts") or time.time() * 1000),
                today,
                _truncate_str(body.get("client_id")),
                _truncate_str(body.get("platform")),
                _truncate_str(body.get("version")),
                int(score),
                _truncate_str(body.get("comment"), 500),
            ),
        )
    return JSONResponse({"ok": True})


# ── Stats ───────────────────────────────────────────────────────────────


def _day_window(days: int):
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=max(1, days) - 1)
    return start, end


@router_dashboard.get("/stats/summary")
def stats_summary(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT event, COUNT(*)::int AS n FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s
                GROUP BY event ORDER BY n DESC LIMIT 30""",
            (start, end),
        )
        top = cur.fetchall()
        cur.execute(
            f"SELECT COUNT(*)::int AS n FROM {SCHEMA}.events WHERE day BETWEEN %s AND %s",
            (start, end),
        )
        total = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT COUNT(DISTINCT client_id)::int AS n FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL""",
            (start, end),
        )
        clients = cur.fetchone()["n"]
    return {
        "window_days": days,
        "total_events": total,
        "unique_clients": clients,
        "top_events": top,
    }


@router_dashboard.get("/stats/dau")
def stats_dau(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT to_char(day, 'YYYY-MM-DD') AS day,
                       COUNT(DISTINCT client_id)::int AS dau
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL
                GROUP BY day ORDER BY day""",
            (start, end),
        )
        return {"series": cur.fetchall()}


@router_dashboard.get("/stats/crash_free")
def stats_crash_free(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    """1 - (sessions with ≥1 crash) / (total sessions). 2026 mobile baseline."""
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(DISTINCT session_id)::int AS n
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND session_id IS NOT NULL""",
            (start, end),
        )
        total = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT COUNT(DISTINCT session_id)::int AS n
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND session_id IS NOT NULL
                AND event='crash'""",
            (start, end),
        )
        crashed = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT to_char(e.day, 'YYYY-MM-DD') AS day,
                       COUNT(DISTINCT e.session_id)::int AS sessions,
                       COUNT(DISTINCT CASE WHEN c.session_id IS NOT NULL
                                           THEN e.session_id END)::int AS crashed
                FROM {SCHEMA}.events e
                LEFT JOIN {SCHEMA}.events c
                  ON c.session_id = e.session_id AND c.event='crash'
                WHERE e.day BETWEEN %s AND %s AND e.session_id IS NOT NULL
                GROUP BY e.day ORDER BY e.day""",
            (start, end),
        )
        daily = cur.fetchall()
    return {
        "sessions": total,
        "crashed_sessions": crashed,
        "crash_free_rate": (1 - (crashed / total)) if total else None,
        "series": [
            {
                "day": r["day"],
                "sessions": r["sessions"],
                "crashed": r["crashed"],
                "rate": (1 - (r["crashed"] / r["sessions"])) if r["sessions"] else None,
            }
            for r in daily
        ],
    }


@router_dashboard.get("/stats/startup_funnel")
def stats_startup_funnel(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(*)::int AS n FROM {SCHEMA}.events
                WHERE event='startup_ok' AND day BETWEEN %s AND %s""",
            (start, end),
        )
        ok = cur.fetchone()["n"]
        cur.execute(
            f"""SELECT props->>'step' AS step,
                       props->>'code' AS code,
                       COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='startup_fail' AND day BETWEEN %s AND %s
                GROUP BY step, code ORDER BY n DESC""",
            (start, end),
        )
        fails = cur.fetchall()
    total = ok + sum(r["n"] for r in fails)
    return {
        "window_days": days,
        "total": total,
        "ok": ok,
        "failures": fails,
        "ok_rate": (ok / total) if total else None,
    }


@router_dashboard.get("/stats/connection_health")
def stats_connection_health(days: int = 1, _user: str = Depends(require_dashboard_auth)):
    """MTTI inputs: failure volume, top failing step, and repair outcomes."""
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT
                  COUNT(*)::int AS total,
                  COUNT(*) FILTER (
                    WHERE COALESCE(
                      props->>'step',
                      props->>'code',
                      props->>'error_class',
                      props->>'reason'
                    ) IS NOT NULL
                  )::int AS identified
                FROM {SCHEMA}.events
                WHERE event='connect_failed' AND day BETWEEN %s AND %s""",
            (start, end),
        )
        connect = cur.fetchone()

        cur.execute(
            f"""SELECT platform, COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='connect_failed' AND day BETWEEN %s AND %s
                GROUP BY platform ORDER BY n DESC LIMIT 12""",
            (start, end),
        )
        by_platform = cur.fetchall()

        cur.execute(
            f"""SELECT COALESCE(
                       props->>'step',
                       props->>'code',
                       props->>'error_class',
                       props->>'reason',
                       'unknown'
                     ) AS reason,
                     COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event IN ('connect_failed', 'startup_fail')
                  AND day BETWEEN %s AND %s
                GROUP BY reason ORDER BY n DESC LIMIT 20""",
            (start, end),
        )
        top_reasons = cur.fetchall()

        cur.execute(
            f"""SELECT COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='diagnostic_export' AND day BETWEEN %s AND %s""",
            (start, end),
        )
        diagnostic_exports = cur.fetchone()["n"]

        cur.execute(
            f"""SELECT props->>'action' AS action,
                       props->>'ok' AS ok,
                       COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='connection_repair_result'
                  AND day BETWEEN %s AND %s
                GROUP BY action, ok ORDER BY action, ok""",
            (start, end),
        )
        repair_actions = cur.fetchall()

        cur.execute(
            f"""SELECT server_ts, event, platform, version,
                       props->>'step' AS step,
                       props->>'code' AS code,
                       props->>'error_class' AS error_class,
                       props->>'reason' AS reason,
                       props->>'action' AS action,
                       props->>'ok' AS ok
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s
                  AND (
                    event IN ('connect_failed', 'startup_fail')
                    OR (
                      event='connection_repair_result'
                      AND props->>'ok'='false'
                    )
                  )
                ORDER BY server_ts DESC LIMIT 50""",
            (start, end),
        )
        recent = cur.fetchall()

    total = connect["total"] or 0
    identified = connect["identified"] or 0
    return {
        "window_days": days,
        "connect_failed": total,
        "identified_connect_failed": identified,
        "identified_rate": (identified / total) if total else None,
        "diagnostic_exports": diagnostic_exports,
        "by_platform": by_platform,
        "top_reasons": top_reasons,
        "repair_actions": repair_actions,
        "recent_failures": recent,
    }


@router_dashboard.get("/stats/errors")
def stats_errors(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT props->>'type' AS type,
                       props->>'src' AS src,
                       COUNT(*)::int AS n
                FROM {SCHEMA}.events
                WHERE event='crash' AND day BETWEEN %s AND %s
                GROUP BY type, src ORDER BY n DESC LIMIT 30""",
            (start, end),
        )
        return {"top_errors": cur.fetchall()}


@router_dashboard.get("/stats/versions")
def stats_versions(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT platform, version, COUNT(DISTINCT client_id)::int AS clients
                FROM {SCHEMA}.events
                WHERE day BETWEEN %s AND %s AND client_id IS NOT NULL
                GROUP BY platform, version ORDER BY platform, clients DESC""",
            (start, end),
        )
        return {"distribution": cur.fetchall()}


# ── Per-node aggregation (v1 + legacy) ─────────────────────────────────
#
# v1 schema lives in `events.props` (JSONB) — emitted by
# `NodeTelemetry.recordProbeResult` in the client. Closed field set:
#   fp, type, group, target, ok, latency_ms, error_class, status_code,
#   core_version, connection_mode  (+ envelope: client_id, version, …)
#
# Legacy `node_urltest` events land in `node_events` via main.py's
# handwritten ingest. Those don't carry target / status / error class —
# we adapt them into the v1-shaped output by treating each urltest as a
# `transport` sample so the dashboard contract stays single.

NODE_PROBE_RESULT_V1 = "node_probe_result_v1"
PROBE_TARGETS = (
    "transport", "claude", "chatgpt", "google",
    "youtube", "netflix", "github", "other",
)
AI_TARGETS = {"claude", "chatgpt"}
NODE_HEALTH_STATES = (
    "healthy", "suspect", "quarantine_candidate", "quarantined", "ai_blocked",
)
DEFAULT_INSUFFICIENT_THRESHOLD = 3


def _percentile(sorted_lats: list, q: float):
    """Nearest-rank percentile. Mirrors probe_nodes.py / scripts/sre to
    keep Python and dashboard math identical."""
    if not sorted_lats:
        return None
    idx = max(0, min(len(sorted_lats) - 1, int(round(q * (len(sorted_lats) - 1)))))
    return sorted_lats[idx]


def _normalized_probe_error(target: str, ok: bool, status_code, error_class):
    """Server-side safety net for older v1 clients that carried
    status_code but not the normalized error_class yet."""
    if ok:
        return None
    raw = (error_class or "").strip().lower()
    if raw:
        if raw == "socket":
            return "tcp_failed"
        if raw == "handshake":
            return "tls_failed"
        if raw == "dns_fail":
            return "dns_failed"
        if "reality" in raw and "auth" in raw:
            return "reality_auth_failed"
        return raw
    if status_code == 1020:
        return "cloudflare_block"
    if status_code == 403:
        return "ai_blocked" if target in AI_TARGETS else "http_403"
    if status_code == 429:
        return "http_429"
    return "unknown"


def _counter_bump(counter: dict, value) -> None:
    if value is None:
        return
    key = str(value).strip()
    if not key:
        return
    counter[key] = counter.get(key, 0) + 1


def _counter_top(counter: dict):
    if not counter:
        return None
    return max(counter, key=counter.get)


def _int_or_none(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    s = str(value).strip()
    return int(s) if s.isdigit() else None


def _aggregate_v1_node_probe_rows(rows) -> dict:
    """Pure-Python aggregator for `events.event = node_probe_result_v1`.

    Input row shape (extracted by SQL `SELECT props->>'fp' AS fp, …`):
      fp, type, target, ok (bool), latency_ms (int|None),
      status_code (int|None), error_class (str|None),
      connection_mode (str|None), core_version (str|None), client_id,
      xb_server_id, path_class, client_asn, client_cc,
      client_region_coarse.

    Output: `{fp: {type, users(set), samples, per_target: {target: ...}}}`.

    Extracted as a free function so the unit test exercises it
    without needing a live Postgres."""
    by_fp: dict = {}
    for r in rows:
        fp = r.get("fp")
        if not fp:
            continue
        node = by_fp.setdefault(fp, {
            "type": r.get("type"),
            "users": set(),
            "samples": 0,
            "per_target": {},
            "xb_server_ids": {},
            "path_classes": {},
            "client_asns": {},
            "client_countries": {},
            "client_regions": {},
            "client_carriers": {},
        })
        node["samples"] += 1
        cid = r.get("client_id")
        if cid:
            node["users"].add(cid)
        _counter_bump(node["xb_server_ids"], _int_or_none(r.get("xb_server_id")))
        _counter_bump(node["path_classes"], r.get("path_class"))
        _counter_bump(node["client_asns"], _int_or_none(r.get("client_asn")))
        _counter_bump(node["client_countries"], r.get("client_cc"))
        _counter_bump(node["client_regions"], r.get("client_region_coarse"))
        _counter_bump(node["client_carriers"], r.get("client_carrier"))
        target = (r.get("target") or "other")
        if target not in PROBE_TARGETS:
            target = "other"
        t = node["per_target"].setdefault(target, {
            "attempts": 0, "ok": 0,
            "latencies": [],
            "status_buckets": {},
            "error_buckets": {},
        })
        t["attempts"] += 1
        if r.get("ok"):
            t["ok"] += 1
        lat = r.get("latency_ms")
        if isinstance(lat, (int, float)) and lat > 0:
            t["latencies"].append(int(lat))
        st = r.get("status_code")
        if isinstance(st, (int, float)):
            key = str(int(st))
            t["status_buckets"][key] = t["status_buckets"].get(key, 0) + 1
        ec = _normalized_probe_error(target, bool(r.get("ok")), st, r.get("error_class"))
        if ec:
            t["error_buckets"][ec] = t["error_buckets"].get(ec, 0) + 1
    return by_fp


def _derive_node_state(per_target: dict, node_type: str | None) -> tuple[str, str | None]:
    """P7 candidate state-machine foundation.

    This does not quarantine production traffic by itself. It only labels
    dashboard rows so SRE can review candidates with human approval."""
    ai_failures = 0
    for target in AI_TARGETS:
        target_record = per_target.get(target) or {}
        buckets = target_record.get("error_buckets") or {}
        status_buckets = target_record.get("status_buckets") or {}
        ai_failures += sum(
            buckets.get(k, 0)
            for k in ("ai_blocked", "cloudflare_block", "http_403", "http_429")
        )
        ai_failures += sum(status_buckets.get(k, 0) for k in ("403", "429", "1020"))
    if ai_failures > 0:
        return "ai_blocked", "AI target returned 403/429/1020 while transport may still work"

    reality_failures = 0
    for t in per_target.values():
        buckets = t.get("error_buckets") or {}
        reality_failures += buckets.get("reality_auth_failed", 0)
    if reality_failures >= 2 and (node_type or "").lower() == "vless":
        return "quarantine_candidate", "repeated Reality authentication failures"

    transport = per_target.get("transport")
    if transport:
        attempts = transport.get("attempts") or 0
        success_rate = transport.get("success_rate")
        timeout_rate = transport.get("timeout_rate")
        if attempts >= 3 and (
            (success_rate is not None and success_rate < 0.5)
            or (timeout_rate is not None and timeout_rate >= 0.5)
        ):
            return "suspect", "transport timeout/error rate high"
        if attempts >= 3 and success_rate is not None and success_rate >= 0.8:
            return "healthy", None

    return "suspect", "insufficient or mixed probe evidence"


def _aggregate_legacy_urltest_rows(rows) -> dict:
    """Adapt `node_events.event = 'urltest'` rows into the v1-shaped
    structure so the response schema stays identical regardless of
    data source. Treats each urltest hit as a `transport` sample.
    delay_ms <= 0 means timeout; reason populates error_buckets."""
    by_fp: dict = {}
    for r in rows:
        fp = r.get("fp")
        if not fp:
            continue
        node = by_fp.setdefault(fp, {
            "type": r.get("type"),
            "users": set(),
            "samples": 0,
            "per_target": {},
        })
        node["samples"] += 1
        cid = r.get("client_id")
        if cid:
            node["users"].add(cid)
        t = node["per_target"].setdefault("transport", {
            "attempts": 0, "ok": 0,
            "latencies": [],
            "status_buckets": {},
            "error_buckets": {},
        })
        t["attempts"] += 1
        ok_int = r.get("ok")
        is_ok = (ok_int == 1) or (ok_int is True)
        if is_ok:
            t["ok"] += 1
        delay = r.get("delay_ms")
        if isinstance(delay, (int, float)) and delay > 0:
            t["latencies"].append(int(delay))
        if not is_ok:
            reason = r.get("reason") or "timeout"
            t["error_buckets"][reason] = t["error_buckets"].get(reason, 0) + 1
    return by_fp


def _shape_node(fp: str, agg: dict, region, min_samples: int) -> dict:
    """Render one fp's aggregation into the public response schema."""
    per_target_out = {}
    for target, t in agg["per_target"].items():
        lats = sorted(t["latencies"])
        attempts = t["attempts"]
        ok = t["ok"]
        timeouts = sum(
            v for k, v in t["error_buckets"].items() if k == "timeout"
        )
        top_err = (
            max(t["error_buckets"], key=t["error_buckets"].get)
            if t["error_buckets"] else None
        )
        per_target_out[target] = {
            "attempts": attempts,
            "ok": ok,
            "success_rate": (ok / attempts) if attempts else None,
            "timeout_rate": (timeouts / attempts) if attempts else None,
            "p50_ms": _percentile(lats, 0.5),
            "p95_ms": _percentile(lats, 0.95),
            "p99_ms": _percentile(lats, 0.99),
            "top_error_class": top_err,
            # Empty maps drop to None to keep payload lean — JSONB
            # `{}` and `null` round-trip differently, dashboard reads
            # null as "no breakdown".
            "status_buckets": t["status_buckets"] or None,
            "error_buckets": t["error_buckets"] or None,
        }
    state, state_reason = _derive_node_state(per_target_out, agg["type"])
    return {
        "fp": fp,
        "type": agg["type"],
        "region": region,
        "top_xb_server_id": _int_or_none(_counter_top(agg.get("xb_server_ids") or {})),
        "xb_server_ids": agg.get("xb_server_ids") or None,
        "top_path_class": _counter_top(agg.get("path_classes") or {}),
        "path_classes": agg.get("path_classes") or None,
        "top_client_asn": _int_or_none(_counter_top(agg.get("client_asns") or {})),
        "client_asns": agg.get("client_asns") or None,
        "client_countries": agg.get("client_countries") or None,
        "client_regions": agg.get("client_regions") or None,
        "top_client_carrier": _counter_top(agg.get("client_carriers") or {}),
        "client_carriers": agg.get("client_carriers") or None,
        "state": state,
        "state_reason": state_reason,
        "requires_human": state in ("quarantine_candidate", "quarantined"),
        "users": len(agg["users"]),
        "samples": agg["samples"],
        "per_target": per_target_out,
        "insufficient_data": agg["samples"] < min_samples,
    }


def _node_rollup(nodes: list) -> dict:
    """Group-level by-target rollup so dashboard can show 'this group's
    Claude success rate' separate from 'transport success rate' instead
    of conflating the two."""
    by_target: dict = {}
    by_path_class: dict = {}
    by_client_asn: dict = {}
    by_client_carrier: dict = {}
    for n in nodes:
        for target, t in n.get("per_target", {}).items():
            r = by_target.setdefault(target, {"attempts": 0, "ok": 0})
            r["attempts"] += t.get("attempts", 0)
            r["ok"] += t.get("ok", 0)
        for path_class, samples in (n.get("path_classes") or {}).items():
            r = by_path_class.setdefault(path_class, {"nodes": 0, "samples": 0})
            r["nodes"] += 1
            r["samples"] += samples
        for asn, samples in (n.get("client_asns") or {}).items():
            r = by_client_asn.setdefault(asn, {"nodes": 0, "samples": 0})
            r["nodes"] += 1
            r["samples"] += samples
        for carrier, samples in (n.get("client_carriers") or {}).items():
            r = by_client_carrier.setdefault(carrier, {"nodes": 0, "samples": 0})
            r["nodes"] += 1
            r["samples"] += samples
    for r in by_target.values():
        r["success_rate"] = (r["ok"] / r["attempts"]) if r["attempts"] else None
    return {
        "total_nodes": len(nodes),
        "by_target_overall": by_target,
        "by_path_class": by_path_class,
        "by_client_asn": by_client_asn,
        "by_client_carrier": by_client_carrier,
    }


@router_dashboard.get("/stats/nodes")
def stats_nodes(
    days: int = 1,
    limit: int = 200,
    min_samples: int = DEFAULT_INSUFFICIENT_THRESHOLD,
    _user: str = Depends(require_dashboard_auth),
):
    """Per-node health derived from `node_probe_result_v1` (preferred)
    falling back to legacy `node_urltest` aggregation when no v1 events
    exist in the window — single response shape regardless of source.

    The v1 path reads directly from `events.props` (JSONB), which
    deliberately avoids touching main.py's handwritten ingest. Adding
    v1 to `_extract_node_rows` would require a careful production
    deploy of main.py; reading JSONB from `events` is a pure dashboard
    change that can ship independently.

    Region is decorated from `node_identity` (populated by
    `node_inventory` events). For nodes whose identity hasn't been
    indexed yet, region is null."""
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT
                  props->>'fp'                       AS fp,
                  props->>'type'                     AS type,
                  props->>'target'                   AS target,
                  (props->>'ok')::boolean            AS ok,
                  NULLIF(props->>'latency_ms', '')::int   AS latency_ms,
                  NULLIF(props->>'status_code', '')::int  AS status_code,
                  props->>'error_class'              AS error_class,
                  CASE WHEN props->>'xb_server_id' ~ '^[0-9]+$'
                       THEN (props->>'xb_server_id')::int
                       ELSE NULL END                  AS xb_server_id,
                  props->>'path_class'                AS path_class,
                  CASE WHEN props->>'client_asn' ~ '^[0-9]+$'
                       THEN (props->>'client_asn')::int
                       ELSE NULL END                  AS client_asn,
                  props->>'client_cc'                 AS client_cc,
                  props->>'client_region_coarse'      AS client_region_coarse,
                  props->>'client_carrier'            AS client_carrier,
                  client_id
                FROM {SCHEMA}.events
                WHERE event = %s
                  AND day BETWEEN %s AND %s
                  AND props->>'fp' IS NOT NULL""",
            (NODE_PROBE_RESULT_V1, start, end),
        )
        v1_rows = cur.fetchall()
        cur.execute(
            f"""SELECT current_fp, region FROM {SCHEMA}.node_identity
                WHERE region IS NOT NULL""",
        )
        region_by_fp = {r["current_fp"]: r["region"] for r in cur.fetchall()}

        legacy_rows = []
        legacy_count = 0
        if not v1_rows:
            cur.execute(
                f"""SELECT fp, type, ok, delay_ms, reason, client_id
                    FROM {SCHEMA}.node_events
                    WHERE event = 'urltest'
                      AND day BETWEEN %s AND %s
                      AND fp IS NOT NULL""",
                (start, end),
            )
            legacy_rows = cur.fetchall()
            legacy_count = len(legacy_rows)

    if v1_rows:
        agg = _aggregate_v1_node_probe_rows(v1_rows)
        data_source = "node_probe_result_v1"
    else:
        agg = _aggregate_legacy_urltest_rows(legacy_rows)
        data_source = "node_urltest_legacy"

    nodes = [
        _shape_node(fp, node_agg, region_by_fp.get(fp), min_samples)
        for fp, node_agg in agg.items()
    ]
    nodes.sort(key=lambda n: (n["insufficient_data"], -n["samples"]))

    return {
        "window_days": days,
        "data_source": data_source,
        "v1_samples": len(v1_rows),
        "legacy_samples": legacy_count,
        "node_count": len(nodes),
        "min_samples_threshold": min_samples,
        "nodes": nodes[:limit],
        "rollup": _node_rollup(nodes),
    }


@router_dashboard.get("/stats/node_health")
def stats_node_health(
    days: int = 1,
    limit: int = 200,
    min_samples: int = DEFAULT_INSUFFICIENT_THRESHOLD,
    _user: str = Depends(require_dashboard_auth),
):
    """Backward-compatible alias for incident runbooks that still probe
    `/stats/node_health`. The canonical endpoint is `/stats/nodes`."""
    return stats_nodes(
        days=days,
        limit=limit,
        min_samples=min_samples,
        _user=_user,
    )


@router_dashboard.get("/stats/nps")
def stats_nps(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT COUNT(*)::int AS total,
                       COALESCE(SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END),0)::int AS promoters,
                       COALESCE(SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END),0)::int AS detractors
                FROM {SCHEMA}.nps_responses WHERE day BETWEEN %s AND %s""",
            (start, end),
        )
        agg = cur.fetchone()
        cur.execute(
            f"""SELECT ts, score, comment, platform, version
                FROM {SCHEMA}.nps_responses
                WHERE day BETWEEN %s AND %s
                  AND comment IS NOT NULL AND comment <> ''
                ORDER BY ts DESC LIMIT 20""",
            (start, end),
        )
        comments = cur.fetchall()
    total = agg["total"] or 0
    if total:
        nps = ((agg["promoters"] / total) - (agg["detractors"] / total)) * 100
    else:
        nps = None
    return {
        "total_responses": total,
        "promoters": agg["promoters"] or 0,
        "detractors": agg["detractors"] or 0,
        "nps": round(nps, 1) if nps is not None else None,
        "recent_comments": comments,
    }


# ── Admin: synthetic data cleanup ───────────────────────────────────────
#
# Release-gate ingest tests POST events with `client_id` like
# `release-gate-<run_id>` and active-probe results with `region =
# 'release-gate'`. This endpoint cleans them so production stats stay
# accurate. Protected by dashboard auth — same trust boundary as the
# /admin/flags writer.


@router_dashboard.post("/admin/synthetic-cleanup")
async def admin_synthetic_cleanup(
    request: Request,
    _user: str = Depends(require_dashboard_auth),
):
    body = await request.json()
    prefix = (body.get("client_id_prefix") or "").strip()
    region = (body.get("active_probe_region") or "").strip()
    if not prefix and not region:
        raise HTTPException(
            status_code=400,
            detail="client_id_prefix or active_probe_region required",
        )
    deleted = {"events": 0, "active_probe_runs": 0, "active_probe_results": 0}
    with db() as c, c.cursor() as cur:
        if prefix:
            cur.execute(
                f"DELETE FROM {SCHEMA}.events "
                f"WHERE client_id LIKE %s",
                (prefix + "%",),
            )
            deleted["events"] = cur.rowcount or 0
        if region:
            cur.execute(
                f"DELETE FROM {SCHEMA}.active_probe_results "
                f"WHERE region = %s",
                (region,),
            )
            deleted["active_probe_results"] = cur.rowcount or 0
            cur.execute(
                f"DELETE FROM {SCHEMA}.active_probe_runs "
                f"WHERE region = %s",
                (region,),
            )
            deleted["active_probe_runs"] = cur.rowcount or 0
    return {"ok": True, "deleted": deleted}


# ── P7 node state machine ───────────────────────────────────────────────
#
# Reads the same RUM aggregation as `/stats/nodes` (and, when present,
# the active-probe results) and writes a label per node into
# `node_state`. Only POST .../review can move a node into `quarantined`
# — automation only ever sets `quarantine_candidate` and flips
# `requires_human`. See p7_node_state_machine.md for the full state
# transition table.

NODE_STATES_AUTO = {
    "healthy", "suspect", "quarantine_candidate",
    "ai_blocked", "ai_suspect", "recovered",
}
NODE_STATES_HUMAN = {"quarantined"}
ALL_NODE_STATES = NODE_STATES_AUTO | NODE_STATES_HUMAN
SUSPECT_TIMEOUT_THRESHOLD = 0.5
SUSPECT_SUCCESS_THRESHOLD = 0.5
HEALTHY_SUCCESS_THRESHOLD = 0.8
QUARANTINE_CANDIDATE_RUM_FAIL_THRESHOLD = 3
RECOVERY_OBSERVATION_HOURS = 6


def require_sre_auth(request: Request) -> str:
    """Token-protected SRE access. Bearer or X-SRE-Token; same secret.

    Configured via TELEMETRY_SRE_TOKEN. If unset, every SRE call returns
    503 — a safer default than 401 because it tells ops "you forgot to
    deploy the secret" instead of "your token is wrong"."""
    if not SRE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SRE token not configured (TELEMETRY_SRE_TOKEN unset)",
        )
    auth = request.headers.get("authorization") or ""
    token = ""
    if auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        token = request.headers.get("x-sre-token", "").strip()
    if not token or not secrets.compare_digest(token, SRE_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid sre token",
        )
    return "sre"


def require_active_probe_auth(request: Request) -> str:
    """Same shape as require_sre_auth but uses ACTIVE_PROBE_TOKEN.

    Separate token so a runner key leak doesn't grant review/quarantine
    powers — the runner can only POST results, not change node state."""
    if not ACTIVE_PROBE_TOKEN:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="active probe token not configured",
        )
    auth = request.headers.get("authorization") or ""
    token = ""
    if auth.lower().startswith("bearer "):
        token = auth[7:].strip()
    if not token:
        token = request.headers.get("x-probe-token", "").strip()
    if not token or not secrets.compare_digest(token, ACTIVE_PROBE_TOKEN):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="invalid active probe token",
        )
    return "probe"


def _classify_node_state(
    rum_per_target: dict,
    probe_per_target: dict | None,
    node_type: str | None,
    previous_state: str | None,
) -> tuple[str, str | None, dict]:
    """Pure function — easy to unit-test without DB.

    Inputs:
      rum_per_target    — output of `_shape_node`'s per_target dict
      probe_per_target  — same shape, derived from active-probe rows;
                          may be None when no active probe data yet
      node_type         — protocol (vless / trojan / hysteria2 / …)
      previous_state    — last state from node_state, may be None on
                          first observation; gates `recovered` paths
    Returns (next_state, reason, evidence_dict).

    Evidence is logged into node_state_transitions.evidence_json so
    later review can re-derive the call without re-querying raw rows.
    """
    rum_per_target = rum_per_target or {}
    probe_per_target = probe_per_target or {}
    evidence: dict = {
        "rum": {
            t: {k: v for k, v in r.items() if k in (
                "attempts", "ok", "success_rate", "timeout_rate",
                "top_error_class",
            )}
            for t, r in rum_per_target.items()
        },
        "probe": {
            t: {k: v for k, v in r.items() if k in (
                "attempts", "ok", "success_rate", "timeout_rate",
                "top_error_class",
            )}
            for t, r in probe_per_target.items()
        },
        "node_type": node_type,
        "previous_state": previous_state,
    }

    # AI-target signal first — Claude/ChatGPT 403/1020/429 means the
    # exit IP is rate-limited, not the node itself. ai_blocked must
    # NEVER escalate to quarantined automatically.
    ai_failures = 0
    ai_timeouts = 0
    for tgt in AI_TARGETS:
        rec = (rum_per_target.get(tgt) or {})
        sb = (rec.get("status_buckets") or {})
        eb = (rec.get("error_buckets") or {})
        ai_failures += sum(sb.get(k, 0) for k in ("403", "429", "1020"))
        ai_failures += sum(eb.get(k, 0) for k in
                          ("ai_blocked", "cloudflare_block", "http_403", "http_429"))
        ai_timeouts += sum(eb.get(k, 0) for k in ("timeout", "tls_failed"))

    rum_transport = rum_per_target.get("transport") or {}
    probe_transport = probe_per_target.get("transport") or {}
    rum_attempts = rum_transport.get("attempts") or 0
    probe_attempts = probe_transport.get("attempts") or 0

    # Reality auth specifically: VLESS only, requires confirmed
    # repeated failures (≥ threshold) — single random failure shouldn't
    # quarantine a stable node.
    reality_failures = 0
    for t, r in rum_per_target.items():
        eb = (r.get("error_buckets") or {})
        reality_failures += eb.get("reality_auth_failed", 0)
    if (reality_failures >= QUARANTINE_CANDIDATE_RUM_FAIL_THRESHOLD
        and (node_type or "").lower() == "vless"):
        return (
            "quarantine_candidate",
            f"Reality auth failed {reality_failures} times — needs human review",
            evidence,
        )

    # Active probe vs RUM divergence: if probe success rate is high but
    # RUM is low, label `suspect` — likely user path / ISP issue, not
    # the node. We deliberately do NOT escalate to candidate without
    # multi-region probe corroboration.
    rum_ok = rum_transport.get("success_rate")
    probe_ok = probe_transport.get("success_rate")

    if (rum_attempts >= QUARANTINE_CANDIDATE_RUM_FAIL_THRESHOLD
        and probe_attempts >= QUARANTINE_CANDIDATE_RUM_FAIL_THRESHOLD
        and rum_ok is not None and probe_ok is not None
        and rum_ok < SUSPECT_SUCCESS_THRESHOLD
        and probe_ok < SUSPECT_SUCCESS_THRESHOLD):
        return (
            "quarantine_candidate",
            "RUM and active probe both below 50% — needs human review",
            evidence,
        )

    if ai_failures > 0:
        return (
            "ai_blocked",
            "AI target returned 403/429/1020 — node may still work for non-AI",
            evidence,
        )
    if ai_timeouts > 0 and rum_ok is not None and rum_ok >= HEALTHY_SUCCESS_THRESHOLD:
        return (
            "ai_suspect",
            "AI target timeouts/TLS EOF on otherwise-healthy node",
            evidence,
        )

    if rum_attempts >= 3 and rum_ok is not None:
        if rum_ok >= HEALTHY_SUCCESS_THRESHOLD:
            # If we were in suspect/recovered, mark recovered explicitly
            # so dashboard can show "this used to be suspect".
            if previous_state in ("suspect", "ai_suspect", "ai_blocked"):
                return ("recovered", "RUM success ≥80% over recent window", evidence)
            return ("healthy", None, evidence)
        if rum_ok < SUSPECT_SUCCESS_THRESHOLD:
            return ("suspect", "RUM transport success rate below 50%", evidence)

    # Insufficient data path — keep previous state if we had one,
    # otherwise default suspect (don't pretend it's healthy without
    # evidence).
    if previous_state:
        return (previous_state, "insufficient new evidence — holding state", evidence)
    return ("suspect", "insufficient evidence — default cautious", evidence)


def _evaluate_node_state(
    rum_per_target: dict,
    probe_per_target: dict | None,
    node_type: str | None,
    previous_state: str | None,
) -> dict:
    """Wrapper that returns enough fields to upsert into node_state.

    Centralizes the requires_human flag derivation so every caller agrees
    quarantine_candidate ⇒ requires_human, and quarantined ⇒ requires_human."""
    state, reason, evidence = _classify_node_state(
        rum_per_target, probe_per_target, node_type, previous_state
    )
    rum_t = (rum_per_target or {}).get("transport") or {}
    probe_t = (probe_per_target or {}).get("transport") or {}
    rum_ai = 0
    rum_ai_ok = 0
    for tgt in AI_TARGETS:
        rec = (rum_per_target or {}).get(tgt) or {}
        rum_ai += rec.get("attempts", 0)
        rum_ai_ok += rec.get("ok", 0)
    return {
        "state": state,
        "reason": reason,
        "evidence": evidence,
        "rum_success_rate": rum_t.get("success_rate"),
        "active_probe_success_rate": probe_t.get("success_rate"),
        "ai_success_rate": (rum_ai_ok / rum_ai) if rum_ai else None,
        "reality_auth_failed_count": sum(
            (r.get("error_buckets") or {}).get("reality_auth_failed", 0)
            for r in (rum_per_target or {}).values()
        ),
        "timeout_count": sum(
            (r.get("error_buckets") or {}).get("timeout", 0)
            for r in (rum_per_target or {}).values()
        ),
        "requires_human": state in ("quarantine_candidate", "quarantined"),
        "confidence": min(1.0, max(0.0,
            (rum_t.get("attempts", 0) + probe_t.get("attempts", 0)) / 30.0
        )),
    }


@router_sre.post("/nodes/state/recompute")
async def sre_recompute_state(
    request: Request,
    _: str = Depends(require_sre_auth),
):
    """Re-derive node state from the last `days` of RUM + active probe
    rows. Idempotent — running it twice is a no-op when nothing changed.

    This is the entry point that wires the read-only `_derive_node_state`
    in /stats/nodes into PERSISTED state with audit trail. Triggered by
    cron (every 5 min in production), or manually after a known incident.
    """
    body = {}
    try:
        body = await request.json()
    except Exception:
        body = {}
    days = int(body.get("days", 1) or 1)
    triggered_by = (body.get("triggered_by") or "manual").strip()
    if triggered_by not in ("manual", "cron", "system"):
        triggered_by = "manual"

    start, end = _day_window(days)
    now_ms = int(time.time() * 1000)
    transitions: list[tuple] = []
    upserts = 0

    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT
                  props->>'fp'                       AS fp,
                  props->>'type'                     AS type,
                  props->>'target'                   AS target,
                  (props->>'ok')::boolean            AS ok,
                  NULLIF(props->>'latency_ms', '')::int   AS latency_ms,
                  NULLIF(props->>'status_code', '')::int  AS status_code,
                  props->>'error_class'              AS error_class,
                  client_id
                FROM {SCHEMA}.events
                WHERE event = %s AND day BETWEEN %s AND %s
                  AND props->>'fp' IS NOT NULL""",
            (NODE_PROBE_RESULT_V1, start, end),
        )
        v1_rows = cur.fetchall()
        rum_agg = _aggregate_v1_node_probe_rows(v1_rows)

        # Active probe — same node_fp keyed shape. We synthesize a per_target
        # dict from active_probe_results so the state machine sees the same
        # structure regardless of source.
        cur.execute(
            f"""SELECT node_fp, target,
                       COUNT(*) FILTER (WHERE status='ok')::int    AS ok,
                       COUNT(*)::int                               AS attempts,
                       NULLIF(percentile_cont(0.5) WITHIN GROUP
                              (ORDER BY latency_ms), 0)::int       AS p50_ms
                  FROM {SCHEMA}.active_probe_results
                 WHERE created_at >= %s
                 GROUP BY node_fp, target""",
            (now_ms - days * 86400 * 1000,),
        )
        probe_agg: dict = {}
        for r in cur.fetchall():
            t = probe_agg.setdefault(r["node_fp"], {})
            t[r["target"]] = {
                "attempts": r["attempts"],
                "ok": r["ok"],
                "success_rate": (r["ok"] / r["attempts"]) if r["attempts"] else None,
                "timeout_rate": None,
                "top_error_class": None,
                "status_buckets": None,
                "error_buckets": None,
            }

        # Map rum_agg per_target shape via _shape_node so confidence & buckets
        # carry through identically to the dashboard.
        cur.execute(
            f"SELECT node_fp, current_state FROM {SCHEMA}.node_state",
        )
        prev_states = {r["node_fp"]: r["current_state"] for r in cur.fetchall()}

        for fp, agg in rum_agg.items():
            shaped = _shape_node(fp, agg, region=None, min_samples=3)
            ev = _evaluate_node_state(
                shaped["per_target"],
                probe_agg.get(fp),
                shaped["type"],
                prev_states.get(fp),
            )
            previous = prev_states.get(fp)
            cur.execute(
                f"""INSERT INTO {SCHEMA}.node_state
                      (node_fp, current_state, previous_state, group_name,
                       transport, last_seen_at, last_transition_at, reason,
                       confidence, rum_success_rate, active_probe_success_rate,
                       ai_success_rate, reality_auth_failed_count, timeout_count,
                       requires_human, updated_at, created_at)
                    VALUES (%s, %s, %s, NULL, %s, %s, %s, %s, %s, %s, %s, %s, %s,
                            %s, %s, %s, %s)
                    ON CONFLICT (node_fp) DO UPDATE SET
                      previous_state = CASE
                        WHEN {SCHEMA}.node_state.current_state IS DISTINCT
                          FROM EXCLUDED.current_state
                          THEN {SCHEMA}.node_state.current_state
                        ELSE {SCHEMA}.node_state.previous_state
                      END,
                      current_state = EXCLUDED.current_state,
                      transport = EXCLUDED.transport,
                      last_seen_at = EXCLUDED.last_seen_at,
                      last_transition_at = CASE
                        WHEN {SCHEMA}.node_state.current_state IS DISTINCT
                          FROM EXCLUDED.current_state
                          THEN EXCLUDED.last_transition_at
                        ELSE {SCHEMA}.node_state.last_transition_at
                      END,
                      reason = EXCLUDED.reason,
                      confidence = EXCLUDED.confidence,
                      rum_success_rate = EXCLUDED.rum_success_rate,
                      active_probe_success_rate = EXCLUDED.active_probe_success_rate,
                      ai_success_rate = EXCLUDED.ai_success_rate,
                      reality_auth_failed_count = EXCLUDED.reality_auth_failed_count,
                      timeout_count = EXCLUDED.timeout_count,
                      requires_human = EXCLUDED.requires_human,
                      updated_at = EXCLUDED.updated_at
                    """,
                (
                    fp, ev["state"], previous, shaped.get("type"),
                    now_ms, now_ms, ev["reason"], ev["confidence"],
                    ev["rum_success_rate"], ev["active_probe_success_rate"],
                    ev["ai_success_rate"], ev["reality_auth_failed_count"],
                    ev["timeout_count"], ev["requires_human"], now_ms, now_ms,
                ),
            )
            upserts += 1
            if previous != ev["state"]:
                # Transitions appended only on actual change. Quarantined
                # is never reached automatically — it's set via
                # /nodes/state/{fp}/review.
                if ev["state"] == "quarantined":
                    raise HTTPException(
                        status_code=500,
                        detail="bug: state machine produced quarantined automatically",
                    )
                transitions.append((
                    fp, previous, ev["state"], ev["reason"],
                    json.dumps(ev["evidence"], ensure_ascii=False),
                    triggered_by, ev["requires_human"], now_ms,
                ))

        if transitions:
            psycopg2.extras.execute_values(
                cur,
                f"""INSERT INTO {SCHEMA}.node_state_transitions
                      (node_fp, from_state, to_state, reason, evidence_json,
                       triggered_by, requires_human, created_at) VALUES %s""",
                transitions,
            )

    return {
        "ok": True,
        "upserts": upserts,
        "transitions": len(transitions),
        "triggered_by": triggered_by,
    }


@router_sre.get("/nodes/state")
def sre_list_node_state(
    state: Optional[str] = None,
    requires_human: Optional[bool] = None,
    limit: int = 200,
    _: str = Depends(require_sre_auth),
):
    """List nodes by state. Use `?requires_human=true` to fetch the
    review queue."""
    where = ["1=1"]
    args: list = []
    if state:
        if state not in ALL_NODE_STATES:
            raise HTTPException(status_code=400, detail=f"unknown state: {state}")
        where.append("current_state = %s")
        args.append(state)
    if requires_human is not None:
        where.append("requires_human = %s")
        args.append(bool(requires_human))
    args.append(max(1, min(limit, 1000)))
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT node_fp, current_state, previous_state, transport,
                       reason, confidence, rum_success_rate,
                       active_probe_success_rate, ai_success_rate,
                       reality_auth_failed_count, timeout_count,
                       requires_human, last_seen_at, last_transition_at
                  FROM {SCHEMA}.node_state
                 WHERE {' AND '.join(where)}
                 ORDER BY requires_human DESC, last_transition_at DESC
                 LIMIT %s""",
            tuple(args),
        )
        nodes = cur.fetchall()
    return {"nodes": nodes, "count": len(nodes)}


@router_sre.get("/nodes/state/{node_fp}")
def sre_get_node_state(
    node_fp: str,
    history_limit: int = 20,
    _: str = Depends(require_sre_auth),
):
    if not node_fp or len(node_fp) > 64:
        raise HTTPException(status_code=400, detail="invalid node_fp")
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"SELECT * FROM {SCHEMA}.node_state WHERE node_fp = %s",
            (node_fp,),
        )
        node = cur.fetchone()
        if not node:
            raise HTTPException(status_code=404, detail="node_fp not in state table")
        cur.execute(
            f"""SELECT id, from_state, to_state, reason, triggered_by,
                       requires_human, created_at, evidence_json
                  FROM {SCHEMA}.node_state_transitions
                 WHERE node_fp = %s
                 ORDER BY created_at DESC LIMIT %s""",
            (node_fp, max(1, min(history_limit, 200))),
        )
        history = cur.fetchall()
        cur.execute(
            f"""SELECT id, requested_state, approved_state, reviewer,
                       decision, comment, created_at
                  FROM {SCHEMA}.node_state_reviews
                 WHERE node_fp = %s
                 ORDER BY created_at DESC LIMIT 10""",
            (node_fp,),
        )
        reviews = cur.fetchall()
    return {"node": node, "transitions": history, "reviews": reviews}


@router_sre.post("/nodes/state/{node_fp}/review")
async def sre_review_node_state(
    node_fp: str,
    request: Request,
    _: str = Depends(require_sre_auth),
):
    """Human gate for moves into `quarantined` (and reversals).

    Body: { reviewer, decision, requested_state?, comment? }
      decision: approve | reject | hold

    `approve` of a quarantine_candidate flips current_state to quarantined.
    `reject` returns it to suspect for further observation.
    `hold` records the review without changing state — used when ops
    wants to wait for more data without dropping the candidate flag."""
    body = await request.json()
    reviewer = (body.get("reviewer") or "").strip()
    decision = (body.get("decision") or "").strip().lower()
    comment = (body.get("comment") or "").strip()
    requested_state = (body.get("requested_state") or "").strip().lower()
    if not reviewer or len(reviewer) > 64:
        raise HTTPException(status_code=400, detail="reviewer required")
    if decision not in ("approve", "reject", "hold"):
        raise HTTPException(
            status_code=400,
            detail="decision must be approve|reject|hold",
        )
    now_ms = int(time.time() * 1000)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"SELECT * FROM {SCHEMA}.node_state WHERE node_fp = %s",
            (node_fp,),
        )
        node = cur.fetchone()
        if not node:
            raise HTTPException(status_code=404, detail="node_fp not in state table")

        next_state = node["current_state"]
        approved_state = None
        cur_state = node["current_state"]

        if decision == "approve":
            if requested_state == "quarantined":
                if cur_state != "quarantine_candidate":
                    raise HTTPException(
                        status_code=409,
                        detail=f"cannot approve quarantined from {cur_state}",
                    )
                next_state = "quarantined"
            elif requested_state in ("healthy", "recovered", "suspect"):
                next_state = requested_state
            else:
                raise HTTPException(
                    status_code=400,
                    detail="approve requires requested_state in "
                    "{quarantined, healthy, recovered, suspect}",
                )
            approved_state = next_state
        elif decision == "reject":
            if cur_state == "quarantine_candidate":
                next_state = "suspect"
            elif cur_state == "quarantined":
                # Reject of a quarantined node = re-open observation.
                next_state = "suspect"
            approved_state = next_state

        cur.execute(
            f"""INSERT INTO {SCHEMA}.node_state_reviews
                  (node_fp, requested_state, approved_state, reviewer,
                   decision, comment, created_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s)""",
            (node_fp, requested_state or cur_state, approved_state,
             reviewer, decision, comment, now_ms),
        )

        if next_state != cur_state:
            cur.execute(
                f"""UPDATE {SCHEMA}.node_state SET
                      previous_state = current_state,
                      current_state = %s,
                      requires_human = %s,
                      last_transition_at = %s,
                      updated_at = %s,
                      reason = %s
                    WHERE node_fp = %s""",
                (
                    next_state,
                    next_state in ("quarantine_candidate", "quarantined"),
                    now_ms, now_ms,
                    f"manual review by {reviewer}: {decision}",
                    node_fp,
                ),
            )
            cur.execute(
                f"""INSERT INTO {SCHEMA}.node_state_transitions
                      (node_fp, from_state, to_state, reason, evidence_json,
                       triggered_by, requires_human, created_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
                (
                    node_fp, cur_state, next_state,
                    f"manual review by {reviewer}: {decision}",
                    json.dumps({"comment": comment}, ensure_ascii=False),
                    "manual",
                    next_state in ("quarantine_candidate", "quarantined"),
                    now_ms,
                ),
            )

    return {
        "ok": True,
        "node_fp": node_fp,
        "from_state": cur_state,
        "to_state": next_state,
        "decision": decision,
        "reviewer": reviewer,
    }


# ── P5 active probe ──────────────────────────────────────────────────────


_PROBE_BUCKET: dict = {"window_start": 0, "count": 0}


def _probe_rate_limit() -> None:
    """1-minute sliding bucket. Blunt but adequate for a single runner.

    For multi-region runners ops should use real-rate-limiter middleware;
    this exists so a runaway runner doesn't melt the DB."""
    now = int(time.time())
    window = now // 60
    if _PROBE_BUCKET.get("window_start") != window:
        _PROBE_BUCKET["window_start"] = window
        _PROBE_BUCKET["count"] = 0
    _PROBE_BUCKET["count"] += 1
    if _PROBE_BUCKET["count"] > ACTIVE_PROBE_RATE_LIMIT_PER_MIN:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"active probe rate limit "
            f"({ACTIVE_PROBE_RATE_LIMIT_PER_MIN}/min) exceeded; back off",
            headers={"Retry-After": "60"},
        )


_PROBE_TARGETS_ALLOWED = set(PROBE_TARGETS)
_PROBE_STATUSES_ALLOWED = {"ok", "fail", "timeout", "error"}


def _validate_probe_result(result: dict) -> tuple[bool, str]:
    fp = result.get("node_fp")
    target = result.get("target")
    rstatus = result.get("status")
    if not fp or not isinstance(fp, str) or len(fp) > 64:
        return False, "node_fp missing or oversized"
    if target not in _PROBE_TARGETS_ALLOWED:
        return False, f"target not allowed: {target!r}"
    if rstatus not in _PROBE_STATUSES_ALLOWED:
        return False, f"status not allowed: {rstatus!r}"
    return True, ""


@router_active_probe.post("/results")
async def active_probe_post_results(
    request: Request,
    _: str = Depends(require_active_probe_auth),
):
    """Batch ingest probe results.

    Body:
      {
        "run_id": "...",
        "region": "...",
        "probe_version": "active_probe_runner.py/v1",
        "results": [...]
      }

    Failed validations land in active_probe_dead_letter so we can
    diagnose without blocking the rest of the batch."""
    _probe_rate_limit()
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid json")
    run_id = (body.get("run_id") or "").strip()
    region = (body.get("region") or "").strip()
    probe_version = (body.get("probe_version") or "").strip()
    results = body.get("results")
    if not run_id or len(run_id) > 64:
        raise HTTPException(status_code=400, detail="run_id required (≤64)")
    if not region or len(region) > 32:
        raise HTTPException(status_code=400, detail="region required (≤32)")
    if not isinstance(results, list):
        raise HTTPException(status_code=400, detail="results[] required")
    if len(results) > MAX_PROBE_RESULTS_PER_REQUEST:
        raise HTTPException(
            status_code=413,
            detail=f"results too large (limit {MAX_PROBE_RESULTS_PER_REQUEST})",
        )

    now_ms = int(time.time() * 1000)
    accepted_rows: list[tuple] = []
    dead_rows: list[tuple] = []
    for r in results:
        if not isinstance(r, dict):
            dead_rows.append((run_id, "not_dict", None,
                              "result is not a dict", now_ms))
            continue
        ok, why = _validate_probe_result(r)
        if not ok:
            dead_rows.append((
                run_id, "schema",
                hashlib.sha1(json.dumps(r, sort_keys=True, default=str)
                             .encode("utf-8")).hexdigest()[:16],
                why, now_ms,
            ))
            continue
        accepted_rows.append((
            run_id,
            r.get("node_fp"),
            _truncate_str(r.get("group_name"), 64),
            _truncate_str(r.get("transport"), 24),
            r.get("target"),
            r.get("status"),
            int(r["status_code"]) if isinstance(r.get("status_code"), (int, float)) else None,
            _truncate_str(r.get("error_class"), 64),
            int(r["latency_ms"]) if isinstance(r.get("latency_ms"), (int, float)) else None,
            int(r["timeout_ms"]) if isinstance(r.get("timeout_ms"), (int, float)) else None,
            region,
            probe_version,
            _truncate_str(r.get("sample_id"), 64),
            _truncate_str(r.get("exit_country"), 8),
            _truncate_str(r.get("exit_isp"), 64),
            now_ms,
        ))

    with db() as c, c.cursor() as cur:
        cur.execute(
            f"""INSERT INTO {SCHEMA}.active_probe_runs
                  (run_id, region, probe_version, started_at,
                   finished_at, node_count, target_count, status,
                   error_summary_json)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (run_id) DO UPDATE SET
                  finished_at = EXCLUDED.finished_at,
                  node_count = COALESCE(EXCLUDED.node_count, {SCHEMA}.active_probe_runs.node_count),
                  target_count = COALESCE(EXCLUDED.target_count, {SCHEMA}.active_probe_runs.target_count),
                  status = EXCLUDED.status,
                  error_summary_json = EXCLUDED.error_summary_json""",
            (
                run_id, region, probe_version,
                int(body.get("started_at") or now_ms),
                int(body.get("finished_at") or now_ms),
                int(body.get("node_count")) if isinstance(body.get("node_count"), (int, float)) else None,
                int(body.get("target_count")) if isinstance(body.get("target_count"), (int, float)) else None,
                "ok" if not dead_rows else "partial",
                json.dumps({"dead_letter": len(dead_rows)}, ensure_ascii=False),
            ),
        )
        if accepted_rows:
            psycopg2.extras.execute_values(
                cur,
                f"""INSERT INTO {SCHEMA}.active_probe_results
                      (run_id, node_fp, group_name, transport, target,
                       status, status_code, error_class, latency_ms,
                       timeout_ms, region, probe_version, sample_id,
                       exit_country, exit_isp, created_at) VALUES %s""",
                accepted_rows,
            )
        if dead_rows:
            psycopg2.extras.execute_values(
                cur,
                f"""INSERT INTO {SCHEMA}.active_probe_dead_letter
                      (run_id, reason, payload_hash, error_message, created_at)
                    VALUES %s""",
                dead_rows,
            )
    return {
        "ok": True,
        "run_id": run_id,
        "accepted": len(accepted_rows),
        "dead_letter": len(dead_rows),
    }


@router_active_probe.get("/health")
def active_probe_health(_: str = Depends(require_active_probe_auth)):
    """Lightweight up-check the runner uses to verify auth before posting
    a full batch — avoids retrying a 1MB payload against a dead endpoint."""
    return {"ok": True, "rate_limit_per_min": ACTIVE_PROBE_RATE_LIMIT_PER_MIN}


@router_active_probe.get("/runs")
def active_probe_list_runs(
    region: Optional[str] = None,
    limit: int = 50,
    _: str = Depends(require_active_probe_auth),
):
    args: list = []
    where = ["1=1"]
    if region:
        where.append("region = %s")
        args.append(region)
    args.append(max(1, min(limit, 500)))
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT run_id, region, probe_version, started_at,
                       finished_at, node_count, target_count, status,
                       error_summary_json
                  FROM {SCHEMA}.active_probe_runs
                 WHERE {' AND '.join(where)}
                 ORDER BY started_at DESC LIMIT %s""",
            tuple(args),
        )
        return {"runs": cur.fetchall()}


@router_active_probe.get("/nodes")
def active_probe_list_nodes(
    hours: int = 24,
    region: Optional[str] = None,
    limit: int = 200,
    _: str = Depends(require_active_probe_auth),
):
    """Per-node aggregation across all targets in the last N hours."""
    cutoff_ms = int(time.time() * 1000) - hours * 3600 * 1000
    args: list = [cutoff_ms]
    where = ["created_at >= %s"]
    if region:
        where.append("region = %s")
        args.append(region)
    args.append(max(1, min(limit, 1000)))
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT node_fp,
                       COUNT(*)::int                                AS attempts,
                       COUNT(*) FILTER (WHERE status='ok')::int     AS ok,
                       NULLIF(percentile_cont(0.5) WITHIN GROUP
                              (ORDER BY latency_ms), 0)::int        AS p50_ms,
                       NULLIF(percentile_cont(0.95) WITHIN GROUP
                              (ORDER BY latency_ms), 0)::int        AS p95_ms,
                       MAX(created_at)                              AS last_seen
                  FROM {SCHEMA}.active_probe_results
                 WHERE {' AND '.join(where)}
                 GROUP BY node_fp ORDER BY attempts DESC LIMIT %s""",
            tuple(args),
        )
        rows = cur.fetchall()
    for r in rows:
        r["success_rate"] = (r["ok"] / r["attempts"]) if r["attempts"] else None
    return {"hours": hours, "region": region, "count": len(rows), "nodes": rows}


@router_active_probe.get("/matrix")
def active_probe_matrix(
    hours: int = 24,
    region: Optional[str] = None,
    _: str = Depends(require_active_probe_auth),
):
    """target × {ok, attempts, p95, top_error_class} — the SRE's favorite
    view: 'is Claude broken globally or only on this node?'"""
    cutoff_ms = int(time.time() * 1000) - hours * 3600 * 1000
    args: list = [cutoff_ms]
    where = ["created_at >= %s"]
    if region:
        where.append("region = %s")
        args.append(region)
    with db() as c, _dict_cursor(c) as cur:
        cur.execute(
            f"""SELECT target,
                       COUNT(*)::int                                AS attempts,
                       COUNT(*) FILTER (WHERE status='ok')::int     AS ok,
                       NULLIF(percentile_cont(0.5) WITHIN GROUP
                              (ORDER BY latency_ms), 0)::int        AS p50_ms,
                       NULLIF(percentile_cont(0.95) WITHIN GROUP
                              (ORDER BY latency_ms), 0)::int        AS p95_ms
                  FROM {SCHEMA}.active_probe_results
                 WHERE {' AND '.join(where)}
                 GROUP BY target ORDER BY target""",
            tuple(args),
        )
        targets = cur.fetchall()
        cur.execute(
            f"""SELECT target, error_class, COUNT(*)::int AS n
                  FROM {SCHEMA}.active_probe_results
                 WHERE {' AND '.join(where)} AND status <> 'ok'
                   AND error_class IS NOT NULL
                 GROUP BY target, error_class
                 ORDER BY target, n DESC""",
            tuple(args),
        )
        errors = cur.fetchall()
    by_target_err: dict = {}
    for e in errors:
        by_target_err.setdefault(e["target"], []).append(e)
    for r in targets:
        r["success_rate"] = (r["ok"] / r["attempts"]) if r["attempts"] else None
        r["top_errors"] = by_target_err.get(r["target"], [])[:5]
    return {"hours": hours, "region": region, "targets": targets}


# ── HTML dashboard ──────────────────────────────────────────────────────


@router_dashboard.get("/dashboard", response_class=HTMLResponse)
def dashboard(_user: str = Depends(require_dashboard_auth)) -> HTMLResponse:
    here = os.path.dirname(os.path.abspath(__file__))
    path = os.path.join(here, "dashboard.html")
    try:
        with open(path, "r", encoding="utf-8") as f:
            return HTMLResponse(f.read())
    except FileNotFoundError:
        return HTMLResponse(
            f"<h1>Dashboard HTML not deployed.</h1><p>Expected at: {path}</p>",
            status_code=500,
        )
