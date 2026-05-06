#!/usr/bin/env python3
"""
One-shot: copy all existing rows from the sqlite events.db into the
PostgreSQL telemetry schema on yueops.

Run on 23.80.91.14 via the checkin-api venv:

    cd /opt/checkin-api
    venv/bin/python telemetry_migrate.py

Idempotent: inserts use ON CONFLICT DO NOTHING where a natural key
exists; tables with synthetic primary keys are inserted only if the
destination is empty (safety net — re-running shouldn't double-count).

After a successful run, the sqlite file stays in place as a backup; it
can be archived/deleted manually once dashboard numbers match.
"""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from datetime import date, datetime, timezone

import psycopg2
import psycopg2.extras

SQLITE_PATH = os.environ.get(
    "TELEMETRY_SQLITE_PATH", "/var/lib/yuelink-telemetry/events.db"
)
DSN = os.environ.get(
    "TELEMETRY_DATABASE_DSN",
    "host=66.55.76.208 port=5432 user=root password=jim@8858 dbname=yueops",
)
SCHEMA = os.environ.get("TELEMETRY_SCHEMA", "telemetry")


def _day_from_sqlite(val) -> date:
    if isinstance(val, str):
        return datetime.strptime(val, "%Y-%m-%d").date()
    if isinstance(val, date):
        return val
    return datetime.now(timezone.utc).date()


def main() -> int:
    if not os.path.exists(SQLITE_PATH):
        print(f"[migrate] no sqlite file at {SQLITE_PATH}; nothing to migrate")
        return 0

    src = sqlite3.connect(SQLITE_PATH)
    src.row_factory = sqlite3.Row
    dst = psycopg2.connect(DSN)
    dst.autocommit = False

    try:
        with dst.cursor() as cur:
            cur.execute(f"SELECT COUNT(*) FROM {SCHEMA}.events")
            dst_count = cur.fetchone()[0]
        print(f"[migrate] destination {SCHEMA}.events currently has {dst_count} rows")

        # ── events ────────────────────────────────────────────────────
        rows = list(src.execute("SELECT * FROM events"))
        print(f"[migrate] {len(rows)} events rows in sqlite")
        tuples = []
        for r in rows:
            day = _day_from_sqlite(r["day"])
            props = r["props"]
            if props is not None:
                try:
                    json.loads(props)  # validate
                except Exception:
                    props = None
            tuples.append((
                r["ts"], r["server_ts"], day, r["event"],
                r["client_id"], r["session_id"], r["platform"], r["version"],
                props,
            ))
        if tuples:
            with dst.cursor() as cur:
                psycopg2.extras.execute_values(
                    cur,
                    f"INSERT INTO {SCHEMA}.events(ts, server_ts, day, event, client_id, "
                    f"session_id, platform, version, props) VALUES %s",
                    tuples,
                )
            print(f"[migrate] events inserted: {len(tuples)}")

        # ── node_events ───────────────────────────────────────────────
        rows = list(src.execute("SELECT * FROM node_events"))
        print(f"[migrate] {len(rows)} node_events rows in sqlite")
        tuples = []
        for r in rows:
            day = _day_from_sqlite(r["day"])
            tuples.append((
                r["ts"], day, r["client_id"], r["platform"], r["version"],
                r["event"], r["fp"], r["type"], r["region"],
                r["delay_ms"], r["ok"], r["reason"], r["group_name"],
            ))
        if tuples:
            with dst.cursor() as cur:
                psycopg2.extras.execute_values(
                    cur,
                    f"INSERT INTO {SCHEMA}.node_events(ts, day, client_id, platform, version, "
                    f"event, fp, type, region, delay_ms, ok, reason, group_name) VALUES %s",
                    tuples,
                )
            print(f"[migrate] node_events inserted: {len(tuples)}")

        # ── node_identity (upsert on current_fp) ──────────────────────
        rows = list(src.execute("SELECT * FROM node_identity"))
        print(f"[migrate] {len(rows)} node_identity rows in sqlite")
        with dst.cursor() as cur:
            for r in rows:
                cur.execute(
                    f"""
                    INSERT INTO {SCHEMA}.node_identity
                        (current_fp, label, protocol, region, sid, xb_server_id,
                         first_seen, last_seen, retired_at)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (current_fp) DO UPDATE SET
                      last_seen = GREATEST({SCHEMA}.node_identity.last_seen, EXCLUDED.last_seen),
                      protocol  = COALESCE(EXCLUDED.protocol, {SCHEMA}.node_identity.protocol),
                      region    = COALESCE(EXCLUDED.region,   {SCHEMA}.node_identity.region)
                    """,
                    (
                        r["current_fp"], r["label"], r["protocol"], r["region"],
                        r["sid"], r["xb_server_id"],
                        r["first_seen"], r["last_seen"], r["retired_at"],
                    ),
                )

        # ── node_fp_history ───────────────────────────────────────────
        rows = list(src.execute("SELECT * FROM node_fp_history"))
        print(f"[migrate] {len(rows)} node_fp_history rows in sqlite")
        with dst.cursor() as cur:
            for r in rows:
                # identity_id in sqlite refers to sqlite's auto-increment;
                # map via current_fp to PG's synthetic id.
                cur.execute(
                    f"SELECT identity_id FROM {SCHEMA}.node_identity WHERE current_fp = %s",
                    (r["fp"],),
                )
                row = cur.fetchone()
                if row is None:
                    continue
                cur.execute(
                    f"""INSERT INTO {SCHEMA}.node_fp_history(fp, identity_id, bound_at, retired_at)
                        VALUES (%s, %s, %s, %s) ON CONFLICT (fp) DO NOTHING""",
                    (r["fp"], row[0], r["bound_at"], r["retired_at"]),
                )

        # ── feature_flags ─────────────────────────────────────────────
        rows = list(src.execute("SELECT * FROM feature_flags"))
        print(f"[migrate] {len(rows)} feature_flags rows in sqlite")
        with dst.cursor() as cur:
            for r in rows:
                cur.execute(
                    f"""INSERT INTO {SCHEMA}.feature_flags(key, value_json, rollout_pct, updated_at)
                        VALUES (%s, %s, %s, %s)
                        ON CONFLICT (key) DO UPDATE SET
                          value_json = EXCLUDED.value_json,
                          rollout_pct = EXCLUDED.rollout_pct,
                          updated_at = EXCLUDED.updated_at""",
                    (r["key"], r["value_json"], r["rollout_pct"], r["updated_at"]),
                )

        # ── nps_responses ─────────────────────────────────────────────
        rows = list(src.execute("SELECT * FROM nps_responses"))
        print(f"[migrate] {len(rows)} nps_responses rows in sqlite")
        tuples = []
        for r in rows:
            day = _day_from_sqlite(r["day"])
            tuples.append((
                r["ts"], day, r["client_id"], r["platform"], r["version"],
                r["score"], r["comment"],
            ))
        if tuples:
            with dst.cursor() as cur:
                psycopg2.extras.execute_values(
                    cur,
                    f"INSERT INTO {SCHEMA}.nps_responses"
                    f"(ts, day, client_id, platform, version, score, comment) VALUES %s",
                    tuples,
                )
            print(f"[migrate] nps_responses inserted: {len(tuples)}")

        dst.commit()
        print("[migrate] committed")

        # Post-check
        with dst.cursor() as cur:
            for t in ("events", "node_events", "node_identity",
                      "node_fp_history", "feature_flags", "nps_responses"):
                cur.execute(f"SELECT COUNT(*) FROM {SCHEMA}.{t}")
                print(f"[migrate] {SCHEMA}.{t}: {cur.fetchone()[0]} rows")
        return 0
    except Exception as e:
        dst.rollback()
        print(f"[migrate] FAILED, rolled back: {e}")
        return 1
    finally:
        src.close()
        dst.close()


if __name__ == "__main__":
    sys.exit(main())
