"""
YueLink telemetry — ingest + stats + dashboard.

Drop-in module for the existing FastAPI checkin-api service on 23.80.91.14.
Mount into the existing `app` via:

    from telemetry import router as telemetry_router
    app.include_router(telemetry_router)

Exposes (all under /api/client/telemetry):

    POST /                         ingest a batch (what the app already sends)
    GET  /stats/summary            top events + counts, last N days
    GET  /stats/dau                daily active clients, last N days
    GET  /stats/startup_funnel     8-step funnel: ok vs fail by step
    GET  /stats/errors             top error types, last N days
    GET  /stats/versions           version distribution
    GET  /dashboard                simple HTML dashboard (Basic Auth)

Stats endpoints require Basic Auth using TELEMETRY_DASHBOARD_USER /
TELEMETRY_DASHBOARD_PASSWORD env vars (defaults disabled — you MUST set
them before deploying).

SQLite backing: /var/lib/yuelink-telemetry/events.db (created on first use).
Auto-prunes events older than 90 days on a 1/1000 sample basis.
"""

from __future__ import annotations

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

# Hard caps on what we accept per call. Anything over is silently dropped.
MAX_EVENTS_PER_REQUEST = 200
MAX_EVENT_NAME_LEN = 64
MAX_PROP_VALUE_LEN = 120

router = APIRouter(prefix="/api/client/telemetry", tags=["telemetry"])
security = HTTPBasic()


# ── DB plumbing ─────────────────────────────────────────────────────────

_SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    ts          INTEGER NOT NULL,            -- milliseconds since epoch (client)
    server_ts   INTEGER NOT NULL,            -- milliseconds since epoch (server)
    day         TEXT NOT NULL,               -- server day, YYYY-MM-DD UTC
    event       TEXT NOT NULL,
    client_id   TEXT,
    session_id  TEXT,
    platform    TEXT,
    version     TEXT,
    props       TEXT                         -- JSON blob of remaining props
);
CREATE INDEX IF NOT EXISTS idx_events_day ON events(day);
CREATE INDEX IF NOT EXISTS idx_events_event ON events(event);
CREATE INDEX IF NOT EXISTS idx_events_client ON events(client_id);
CREATE INDEX IF NOT EXISTS idx_events_day_event ON events(day, event);
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
    # 1/1000 requests trigger a cleanup — avoids blocking hot path.
    if secrets.randbelow(1000) != 0:
        return
    cutoff_day = (
        datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    ).strftime("%Y-%m-%d")
    with db() as c:
        c.execute("DELETE FROM events WHERE day < ?", (cutoff_day,))


# ── Auth for stats endpoints ────────────────────────────────────────────


def require_dashboard_auth(
    credentials: HTTPBasicCredentials = Depends(security),
) -> str:
    if not DASHBOARD_USER or not DASHBOARD_PASSWORD:
        # Fail closed — deploy must set env vars before dashboard is usable.
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
}


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

    rows = []
    for e in events:
        if not isinstance(e, dict):
            continue
        name = (e.get("event") or "").strip()
        if not name or len(name) > MAX_EVENT_NAME_LEN:
            continue
        ts = e.get("ts")
        if not isinstance(ts, (int, float)):
            ts = server_ts
        props = {
            k: _truncate(v)
            for k, v in e.items()
            if k not in _RESERVED_KEYS and _is_simple_scalar(v)
        }
        rows.append(
            (
                int(ts),
                server_ts,
                today,
                name,
                _truncate(e.get("client_id")),
                _truncate(e.get("session_id")),
                _truncate(e.get("platform")),
                _truncate(e.get("version")),
                json.dumps(props, ensure_ascii=False) if props else None,
            )
        )

    if not rows:
        return JSONResponse({"ok": True, "count": 0})

    with db() as c:
        c.executemany(
            "INSERT INTO events(ts, server_ts, day, event, client_id, "
            "session_id, platform, version, props) "
            "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
            rows,
        )

    _maybe_prune()
    return JSONResponse({"ok": True, "count": len(rows)})


def _is_simple_scalar(v) -> bool:
    return v is None or isinstance(v, (str, int, float, bool))


def _truncate(v: Optional[object]) -> Optional[str]:
    if v is None:
        return None
    s = str(v)
    return s[:MAX_PROP_VALUE_LEN] if len(s) > MAX_PROP_VALUE_LEN else s


# ── Stats ───────────────────────────────────────────────────────────────


def _day_window(days: int) -> tuple[str, str]:
    end = datetime.now(timezone.utc).date()
    start = end - timedelta(days=max(1, days) - 1)
    return start.strftime("%Y-%m-%d"), end.strftime("%Y-%m-%d")


@router.get("/stats/summary")
def stats_summary(
    days: int = 7,
    _user: str = Depends(require_dashboard_auth),
):
    start, end = _day_window(days)
    with db() as c:
        top_events = c.execute(
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
        "top_events": [dict(r) for r in top_events],
    }


@router.get("/stats/dau")
def stats_dau(
    days: int = 30,
    _user: str = Depends(require_dashboard_auth),
):
    start, end = _day_window(days)
    with db() as c:
        rows = c.execute(
            "SELECT day, COUNT(DISTINCT client_id) AS dau FROM events "
            "WHERE day BETWEEN ? AND ? AND client_id IS NOT NULL "
            "GROUP BY day ORDER BY day",
            (start, end),
        ).fetchall()
    return {"series": [dict(r) for r in rows]}


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
def stats_errors(
    days: int = 7,
    _user: str = Depends(require_dashboard_auth),
):
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
def stats_versions(
    days: int = 7,
    _user: str = Depends(require_dashboard_auth),
):
    start, end = _day_window(days)
    with db() as c:
        rows = c.execute(
            "SELECT platform, version, COUNT(DISTINCT client_id) AS clients "
            "FROM events WHERE day BETWEEN ? AND ? AND client_id IS NOT NULL "
            "GROUP BY platform, version "
            "ORDER BY platform, clients DESC",
            (start, end),
        ).fetchall()
    return {"distribution": [dict(r) for r in rows]}


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
            "<h1>Dashboard HTML not deployed.</h1>"
            "<p>Expected at: " + path + "</p>",
            status_code=500,
        )
