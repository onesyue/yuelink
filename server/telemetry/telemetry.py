"""
YueLink telemetry — ingest + stats + feature flags + NPS + dashboard.

Drop-in FastAPI APIRouter mounted alongside the existing checkin-api
service on 23.80.91.14.

Under /api/client/telemetry:

    POST /                         ingest a batch (what the app sends)
    GET  /flags                    feature flag evaluation for a client_id
    POST /nps                      NPS score + comment submission
    GET  /stats/summary            top events + counts, last N days  (BasicAuth)
    GET  /stats/dau                daily active clients              (BasicAuth)
    GET  /stats/crash_free         crash-free session rate           (BasicAuth)
    GET  /stats/startup_funnel     8-step funnel ok vs fail          (BasicAuth)
    GET  /stats/errors             top error types                   (BasicAuth)
    GET  /stats/versions           platform × version                (BasicAuth)
    GET  /stats/nodes              node fingerprint health scores    (BasicAuth)
    GET  /stats/nps                NPS aggregate + last comments     (BasicAuth)
    GET  /admin/flags              admin JSON view of current flags  (BasicAuth)
    POST /admin/flags              write a flag value                (BasicAuth)
    GET  /dashboard                single-page HTML dashboard        (BasicAuth)

Store: SQLite at /var/lib/yuelink-telemetry/events.db. Auto-prune events
older than 90 days on a sampled basis.
"""

from __future__ import annotations

import hashlib
import json
import os
import secrets
import sqlite3
import time
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
from typing import Iterator, Optional

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials

# ── Configuration ───────────────────────────────────────────────────────

DB_PATH = os.environ.get(
    "TELEMETRY_DB_PATH", "/var/lib/yuelink-telemetry/events.db"
)
DASHBOARD_USER = os.environ.get("TELEMETRY_DASHBOARD_USER", "")
DASHBOARD_PASSWORD = os.environ.get("TELEMETRY_DASHBOARD_PASSWORD", "")
RETENTION_DAYS = int(os.environ.get("TELEMETRY_RETENTION_DAYS", "90"))

MAX_EVENTS_PER_REQUEST = 200
MAX_EVENT_NAME_LEN = 64
MAX_PROP_VALUE_LEN = 200
MAX_INVENTORY_NODES = 200

router = APIRouter(prefix="/api/client/telemetry", tags=["telemetry"])
security = HTTPBasic()


# ── DB plumbing ─────────────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          INTEGER NOT NULL,
    server_ts   INTEGER NOT NULL,
    day         TEXT NOT NULL,
    event       TEXT NOT NULL,
    client_id   TEXT,
    session_id  TEXT,
    platform    TEXT,
    version     TEXT,
    props       TEXT
);
CREATE INDEX IF NOT EXISTS idx_events_day       ON events(day);
CREATE INDEX IF NOT EXISTS idx_events_event     ON events(event);
CREATE INDEX IF NOT EXISTS idx_events_client    ON events(client_id);
CREATE INDEX IF NOT EXISTS idx_events_session   ON events(session_id);
CREATE INDEX IF NOT EXISTS idx_events_day_event ON events(day, event);

-- node_events: flat per-node rows extracted from node_* telemetry events
-- so queries can scan a narrow table instead of parsing JSON props.
CREATE TABLE IF NOT EXISTS node_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          INTEGER NOT NULL,
    day         TEXT NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    event       TEXT NOT NULL,   -- urltest | connect | select | inventory_item
    fp          TEXT,
    type        TEXT,
    region      TEXT,
    delay_ms    INTEGER,
    ok          INTEGER,          -- 0 / 1, null for inventory_item
    reason      TEXT,
    group_name  TEXT
);
CREATE INDEX IF NOT EXISTS idx_node_events_fp_day ON node_events(fp, day);
CREATE INDEX IF NOT EXISTS idx_node_events_day    ON node_events(day);
CREATE INDEX IF NOT EXISTS idx_node_events_event  ON node_events(event);

-- node_identity: stable identifier per node, rebindable across fp changes
-- (ops bind manually via /admin/node/bind when the panel rotates IPs).
CREATE TABLE IF NOT EXISTS node_identity (
    identity_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    current_fp   TEXT UNIQUE,
    label        TEXT,
    protocol     TEXT,
    region       TEXT,
    sid          TEXT,
    xb_server_id INTEGER,
    first_seen   INTEGER NOT NULL,
    last_seen    INTEGER NOT NULL,
    retired_at   INTEGER
);
CREATE TABLE IF NOT EXISTS node_fp_history (
    fp          TEXT PRIMARY KEY,
    identity_id INTEGER NOT NULL,
    bound_at    INTEGER NOT NULL,
    retired_at  INTEGER,
    FOREIGN KEY (identity_id) REFERENCES node_identity(identity_id)
);

-- feature_flags: admin-controlled flags returned to clients
CREATE TABLE IF NOT EXISTS feature_flags (
    key         TEXT PRIMARY KEY,
    value_json  TEXT NOT NULL,         -- JSON-encoded: bool / num / string
    rollout_pct INTEGER DEFAULT 100,   -- 0-100; 100 = all clients
    updated_at  INTEGER NOT NULL
);

-- nps_responses: separate table so comments never live in generic events
CREATE TABLE IF NOT EXISTS nps_responses (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          INTEGER NOT NULL,
    day         TEXT NOT NULL,
    client_id   TEXT,
    platform    TEXT,
    version     TEXT,
    score       INTEGER NOT NULL,
    comment     TEXT
);
CREATE INDEX IF NOT EXISTS idx_nps_day ON nps_responses(day);
"""


def _ensure_db() -> None:
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    with sqlite3.connect(DB_PATH) as c:
        c.executescript(_SCHEMA)


_ensure_db()


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _maybe_prune() -> None:
    if secrets.randbelow(1000) != 0:
        return
    cutoff_day = (
        datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    ).strftime("%Y-%m-%d")
    with db() as c:
        c.execute("DELETE FROM events WHERE day < ?", (cutoff_day,))
        c.execute("DELETE FROM node_events WHERE day < ?", (cutoff_day,))
        c.execute("DELETE FROM nps_responses WHERE day < ?", (cutoff_day,))


# ── Auth for admin/stats endpoints ──────────────────────────────────────


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


def _truncate(v: Optional[object], limit: int = MAX_PROP_VALUE_LEN) -> Optional[str]:
    if v is None:
        return None
    s = str(v)
    return s[:limit] if len(s) > limit else s


def _extract_node_rows(event_name: str, body: dict, day: str) -> list[tuple]:
    """Fan-out node_* events into flat node_events rows."""
    rows: list[tuple] = []
    ts = int(body.get("ts") or 0)
    cid = _truncate(body.get("client_id"))
    platform = _truncate(body.get("platform"))
    version = _truncate(body.get("version"))

    def row(ev: str, fp, typ, region=None, delay_ms=None, ok=None, reason=None, group=None):
        return (
            ts, day, cid, platform, version, ev,
            _truncate(fp, 32),
            _truncate(typ, 24),
            _truncate(region, 16),
            int(delay_ms) if isinstance(delay_ms, (int, float)) else None,
            (1 if ok is True else (0 if ok is False else None)),
            _truncate(reason, 80),
            _truncate(group, 64),
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


@router.post("")
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
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

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

        # Build props bag (scalars only; list-of-scalars/dicts stored in JSON).
        props: dict = {}
        for k, v in e.items():
            if k in _RESERVED_KEYS:
                continue
            if _is_simple_scalar(v):
                props[k] = _truncate(v)
            elif isinstance(v, list):
                cleaned = []
                for item in v[:MAX_INVENTORY_NODES]:
                    if isinstance(item, dict):
                        inner = {
                            ik: _truncate(iv) for ik, iv in item.items()
                            if isinstance(ik, str) and _is_simple_scalar(iv)
                        }
                        if inner:
                            cleaned.append(inner)
                if cleaned:
                    props[k] = cleaned

        event_rows.append((
            int(ts),
            server_ts,
            today,
            name,
            _truncate(e.get("client_id")),
            _truncate(e.get("session_id")),
            _truncate(e.get("platform")),
            _truncate(e.get("version")),
            json.dumps(props, ensure_ascii=False) if props else None,
        ))

        # Fan out node_* into flat rows. Pass the RAW event `e` (not merged
        # with the stringified `props`) so numeric/bool fields keep their
        # original types — the extractor casts them explicitly.
        if name.startswith("node_"):
            node_rows.extend(_extract_node_rows(name, e, today))

    if not event_rows:
        return JSONResponse({"ok": True, "count": 0})

    with db() as c:
        c.executemany(
            "INSERT INTO events(ts, server_ts, day, event, client_id, "
            "session_id, platform, version, props) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            event_rows,
        )
        if node_rows:
            c.executemany(
                "INSERT INTO node_events(ts, day, client_id, platform, version, "
                "event, fp, type, region, delay_ms, ok, reason, group_name) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                node_rows,
            )
            # Upsert node_identity — last_seen keeps moving forward.
            # Region/protocol only update when the incoming row has a non-null
            # value; otherwise a later urltest/connect row (which carries no
            # region) would clobber the good data from an earlier inventory row.
            for r in node_rows:
                fp = r[6]
                typ = r[7]
                region = r[8]
                now_ts = server_ts
                if not fp:
                    continue
                c.execute(
                    "INSERT INTO node_identity(current_fp, protocol, region, "
                    "first_seen, last_seen) VALUES (?, ?, ?, ?, ?) "
                    "ON CONFLICT(current_fp) DO UPDATE SET "
                    "  last_seen=excluded.last_seen, "
                    "  protocol=COALESCE(excluded.protocol, node_identity.protocol), "
                    "  region=COALESCE(excluded.region, node_identity.region)",
                    (fp, typ, region, now_ts, now_ts),
                )

    _maybe_prune()
    return JSONResponse({"ok": True, "count": len(event_rows)})


# ── Feature flags ───────────────────────────────────────────────────────


@router.get("/flags")
def get_flags(
    client_id: str = "",
    platform: str = "",
    version: str = "",
):
    """Return the effective flags for [client_id].

    `rollout_pct` controls the rollout: for each flag we hash
    sha1(key + client_id) to a 0-99 integer and compare with `rollout_pct`.
    This is stable per client, so a user never sees a flag flip just
    because they restarted the app.
    """
    with db() as c:
        rows = c.execute(
            "SELECT key, value_json, rollout_pct FROM feature_flags"
        ).fetchall()
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


@router.get("/admin/flags")
def admin_list_flags(_user: str = Depends(require_dashboard_auth)):
    with db() as c:
        rows = c.execute(
            "SELECT key, value_json, rollout_pct, updated_at "
            "FROM feature_flags ORDER BY key"
        ).fetchall()
    return {"flags": [dict(r) for r in rows]}


@router.post("/admin/flags")
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
    with db() as c:
        c.execute(
            "INSERT INTO feature_flags(key, value_json, rollout_pct, updated_at) "
            "VALUES (?, ?, ?, ?) "
            "ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json, "
            "rollout_pct=excluded.rollout_pct, updated_at=excluded.updated_at",
            (key, json.dumps(value), rollout_pct, int(time.time())),
        )
    return {"ok": True, "key": key}


# ── NPS ─────────────────────────────────────────────────────────────────


@router.post("/nps")
async def nps_submit(request: Request) -> JSONResponse:
    body = await request.json()
    score = body.get("score")
    if not isinstance(score, (int, float)) or score < 0 or score > 10:
        raise HTTPException(status_code=400, detail="score must be 0-10")
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    with db() as c:
        c.execute(
            "INSERT INTO nps_responses(ts, day, client_id, platform, version, "
            "score, comment) VALUES (?, ?, ?, ?, ?, ?, ?)",
            (
                int(body.get("ts") or time.time() * 1000),
                today,
                _truncate(body.get("client_id")),
                _truncate(body.get("platform")),
                _truncate(body.get("version")),
                int(score),
                _truncate(body.get("comment"), 500),
            ),
        )
    return JSONResponse({"ok": True})


# ── Stats ───────────────────────────────────────────────────────────────


def _day_window(days: int) -> tuple[str, str]:
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=max(1, days) - 1)
    return start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")


@router.get("/stats/summary")
def stats_summary(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c:
        top = c.execute(
            "SELECT event, COUNT(*) AS n FROM events "
            "WHERE day BETWEEN ? AND ? GROUP BY event ORDER BY n DESC LIMIT 30",
            (start, end),
        ).fetchall()
        total = c.execute(
            "SELECT COUNT(*) AS n FROM events WHERE day BETWEEN ? AND ?",
            (start, end),
        ).fetchone()["n"]
        clients = c.execute(
            "SELECT COUNT(DISTINCT client_id) AS n FROM events "
            "WHERE day BETWEEN ? AND ? AND client_id IS NOT NULL",
            (start, end),
        ).fetchone()["n"]
    return {
        "window_days": days,
        "total_events": total,
        "unique_clients": clients,
        "top_events": [dict(r) for r in top],
    }


@router.get("/stats/dau")
def stats_dau(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c:
        rows = c.execute(
            "SELECT day, COUNT(DISTINCT client_id) AS dau FROM events "
            "WHERE day BETWEEN ? AND ? AND client_id IS NOT NULL "
            "GROUP BY day ORDER BY day",
            (start, end),
        ).fetchall()
    return {"series": [dict(r) for r in rows]}


@router.get("/stats/crash_free")
def stats_crash_free(
    days: int = 7,
    _user: str = Depends(require_dashboard_auth),
):
    """Crash-free session rate — 2026 standard mobile quality metric.

    `1 - (distinct sessions with crash) / (distinct sessions)`.
    """
    start, end = _day_window(days)
    with db() as c:
        total = c.execute(
            "SELECT COUNT(DISTINCT session_id) AS n FROM events "
            "WHERE day BETWEEN ? AND ? AND session_id IS NOT NULL",
            (start, end),
        ).fetchone()["n"]
        crashed = c.execute(
            "SELECT COUNT(DISTINCT session_id) AS n FROM events "
            "WHERE day BETWEEN ? AND ? AND session_id IS NOT NULL "
            "AND event='crash'",
            (start, end),
        ).fetchone()["n"]
        # Daily series for trending
        daily = c.execute(
            "SELECT e.day, "
            "COUNT(DISTINCT e.session_id) AS sessions, "
            "COUNT(DISTINCT CASE WHEN c.session_id IS NOT NULL THEN e.session_id END) AS crashed "
            "FROM events e LEFT JOIN events c "
            "  ON c.session_id = e.session_id AND c.event='crash' "
            "WHERE e.day BETWEEN ? AND ? AND e.session_id IS NOT NULL "
            "GROUP BY e.day ORDER BY e.day",
            (start, end),
        ).fetchall()
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


@router.get("/stats/startup_funnel")
def stats_startup_funnel(
    days: int = 7,
    _user: str = Depends(require_dashboard_auth),
):
    start, end = _day_window(days)
    with db() as c:
        ok = c.execute(
            "SELECT COUNT(*) AS n FROM events "
            "WHERE event='startup_ok' AND day BETWEEN ? AND ?",
            (start, end),
        ).fetchone()["n"]
        fails = c.execute(
            "SELECT json_extract(props, '$.step') AS step, "
            "json_extract(props, '$.code') AS code, COUNT(*) AS n "
            "FROM events WHERE event='startup_fail' AND day BETWEEN ? AND ? "
            "GROUP BY step, code ORDER BY n DESC",
            (start, end),
        ).fetchall()
    total = ok + sum(r["n"] for r in fails)
    return {
        "window_days": days,
        "total": total,
        "ok": ok,
        "failures": [dict(r) for r in fails],
        "ok_rate": (ok / total) if total else None,
    }


@router.get("/stats/errors")
def stats_errors(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c:
        rows = c.execute(
            "SELECT json_extract(props, '$.type') AS type, "
            "json_extract(props, '$.src') AS src, COUNT(*) AS n "
            "FROM events WHERE event='crash' AND day BETWEEN ? AND ? "
            "GROUP BY type, src ORDER BY n DESC LIMIT 30",
            (start, end),
        ).fetchall()
    return {"top_errors": [dict(r) for r in rows]}


@router.get("/stats/versions")
def stats_versions(days: int = 7, _user: str = Depends(require_dashboard_auth)):
    start, end = _day_window(days)
    with db() as c:
        rows = c.execute(
            "SELECT platform, version, COUNT(DISTINCT client_id) AS clients "
            "FROM events WHERE day BETWEEN ? AND ? AND client_id IS NOT NULL "
            "GROUP BY platform, version ORDER BY platform, clients DESC",
            (start, end),
        ).fetchall()
    return {"distribution": [dict(r) for r in rows]}


@router.get("/stats/nodes")
def stats_nodes(
    days: int = 7,
    limit: int = 50,
    _user: str = Depends(require_dashboard_auth),
):
    """Per-node health score from real-user telemetry.

    Scoring formula:
        latency_score   = max(0, 1 - p95_delay_ms / 2000)    # 2s = 0
        success_score   = urltest_ok_rate
        connect_score   = connect_ok_rate  (if any connects, else 1)
        usage_weight    = log(users + 1) / log(50)
        score = 0.45 * success + 0.35 * latency + 0.20 * connect_score

    Returns 0-100 integer, with insufficient_data flag when `users` < 5
    or `tests` < 10.
    """
    start, end = _day_window(days)
    with db() as c:
        # Pull region from node_identity — urltest/connect rows don't carry
        # it, only inventory_item rows do, and identity upsert propagates
        # the best-known value via COALESCE.
        urltest = c.execute(
            "SELECT ne.fp AS fp, "
            "       COALESCE(ni.protocol, ne.type) AS type, "
            "       ni.region AS region, "
            "       COUNT(*) AS tests, "
            "       SUM(ne.ok) AS ok_count, "
            "       COUNT(DISTINCT ne.client_id) AS users, "
            "       AVG(ne.delay_ms) AS avg_delay, "
            "       MAX(ne.delay_ms) AS max_delay "
            "FROM node_events ne "
            "LEFT JOIN node_identity ni ON ni.current_fp = ne.fp "
            "WHERE ne.event='urltest' AND ne.day BETWEEN ? AND ? "
            "AND ne.fp IS NOT NULL "
            "GROUP BY ne.fp",
            (start, end),
        ).fetchall()
        connect = c.execute(
            "SELECT fp, COUNT(*) AS attempts, SUM(ok) AS ok_count "
            "FROM node_events WHERE event='connect' AND day BETWEEN ? AND ? "
            "AND fp IS NOT NULL GROUP BY fp",
            (start, end),
        ).fetchall()

    connect_map = {r["fp"]: (r["attempts"], r["ok_count"]) for r in connect}

    out = []
    for r in urltest:
        tests = r["tests"] or 0
        oks = r["ok_count"] or 0
        users = r["users"] or 0
        success = (oks / tests) if tests else 0
        avg_delay = r["avg_delay"] or 0
        # p95 approx — use max_delay unless we have enough samples for real p95
        p95_delay = r["max_delay"] or 0
        latency = max(0, 1 - (p95_delay / 2000))
        c_attempts, c_oks = connect_map.get(r["fp"], (0, 0))
        connect_rate = (c_oks / c_attempts) if c_attempts else 1.0
        score = 0.45 * success + 0.35 * latency + 0.20 * connect_rate
        insufficient = users < 5 or tests < 10
        out.append({
            "fp": r["fp"],
            "type": r["type"],
            "region": r["region"],
            "users": users,
            "tests": tests,
            "success_rate": round(success, 3),
            "avg_delay_ms": round(avg_delay, 0),
            "p95_delay_ms": round(p95_delay, 0),
            "connect_attempts": c_attempts,
            "connect_ok_rate": round(connect_rate, 3),
            "score": int(round(score * 100)),
            "insufficient_data": insufficient,
        })

    out.sort(key=lambda x: (x["insufficient_data"], -x["score"]))
    return {"window_days": days, "nodes": out[:limit]}


@router.get("/stats/nps")
def stats_nps(days: int = 30, _user: str = Depends(require_dashboard_auth)):
    """Aggregate NPS + latest comments (most-recent 20)."""
    start, end = _day_window(days)
    with db() as c:
        agg = c.execute(
            "SELECT COUNT(*) AS total, "
            "SUM(CASE WHEN score >= 9 THEN 1 ELSE 0 END) AS promoters, "
            "SUM(CASE WHEN score <= 6 THEN 1 ELSE 0 END) AS detractors "
            "FROM nps_responses WHERE day BETWEEN ? AND ?",
            (start, end),
        ).fetchone()
        comments = c.execute(
            "SELECT ts, score, comment, platform, version FROM nps_responses "
            "WHERE day BETWEEN ? AND ? AND comment IS NOT NULL AND comment != '' "
            "ORDER BY ts DESC LIMIT 20",
            (start, end),
        ).fetchall()
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
        "recent_comments": [dict(r) for r in comments],
    }


# ── HTML dashboard ──────────────────────────────────────────────────────


@router.get("/dashboard", response_class=HTMLResponse)
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
