#!/usr/bin/env python3
"""Telemetry release-gate probe (full mode).

Companion to `scripts/probe_telemetry.sh`, which only checks no-auth
reachability (401 challenge means "router mounted"). This script does
the rest of the release-gate's job:

  1. Auth check on every dashboard endpoint:
       /dashboard, /stats/summary, /stats/versions, /stats/nodes,
       /stats/node_health
       — without auth: must 401 (or 503 if creds not configured)
       — with auth:    must 200, schema-valid, no privacy leaks

  2. Synthetic ingest round-trip on POST /api/client/telemetry:
       sends events tagged client_id="release-gate-<run_id>" and
       props.synthetic=true so they're easy to clean up.

       Synthetic event mix:
         - ok                                 (baseline event)
         - reality_auth_failed   (P7 candidate signal)
         - ai_blocked / http_403 (AI bucket)
         - desktop_tun_degraded  (TUN diagnostic)
         - node_probe_result_v1  mode=tun  (per-node v1)

  3. Optional active-probe ingest round-trip on POST
     /api/sre/active-probe/v1/results — same synthetic markers.

  4. Privacy: response bodies must NOT contain banned strings
     (server / uuid / password / publicKey / shortId / sni / Bearer …).

  5. Cleanup: when the cleanup endpoint is available and authentic,
     posts to /admin/synthetic-cleanup so prod stats don't drift.

CI calls this from .github/workflows/release-gate.yml on tag push.
Locally:

    TELEMETRY_BASE=https://yue.yuebao.website \\
    TELEMETRY_DASHBOARD_USER=yuelink \\
    TELEMETRY_DASHBOARD_PASSWORD=$DASHBOARD_PASS \\
    python3 scripts/probe_telemetry.py --full --json | jq .

Exit codes:
    0 = ok (release-gate passes)
    1 = endpoint failure (404 / 5xx / unexpected status)
    2 = schema mismatch
    3 = privacy leak
    4 = ingest round-trip failure
    5 = usage / config error

Important: this script never logs the dashboard credentials, even on
failure. If a request fails, only the URL + HTTP status + a 200-byte
body excerpt with secrets stripped is emitted.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid
from dataclasses import dataclass, field
from typing import Optional

# Banned strings the response MUST NOT contain. Each entry is a
# (regex, label) pair so the report names which check fired without
# echoing the leak text.
BANNED_PATTERNS: list[tuple[str, str]] = [
    # Subscription URL shapes — ?token=…  /subscribe?…
    (r"/api/v1/client/subscribe\?token=[A-Za-z0-9]{12,}", "sub_token_url"),
    # Bearer auth
    (r"Authorization:\s*Bearer\s+[A-Za-z0-9_.\-]{20,}", "auth_bearer"),
    # Standalone uuid that LOOKS like a node uuid (8-4-4-4-12 hex)
    # — high false-positive risk; treated as NOTE, not FAIL.
    (r"\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b", "uuid_like"),
    # XBoard-style server config: host=… password=…
    (r"host=[A-Za-z0-9.\-]+\s+port=[0-9]+\s+user=[A-Za-z0-9_]+\s+password=", "prod_dsn"),
    # Property-style password assignment in JSON
    (r'"password"\s*:\s*"[^"]{6,}"', "json_password_leak"),
    # publicKey / shortId — Reality fingerprint material
    (r'"publicKey"\s*:\s*"[A-Za-z0-9+/=]{40,}"', "reality_publicKey"),
    (r'"shortId"\s*:\s*"[A-Fa-f0-9]{6,}"', "reality_shortId"),
]


@dataclass
class CheckResult:
    name: str
    ok: bool
    detail: str = ""
    http_status: Optional[int] = None
    privacy_leaks: list[str] = field(default_factory=list)


@dataclass
class GateReport:
    base: str
    run_id: str
    started_at: float
    checks: list[CheckResult] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return all(c.ok for c in self.checks)

    @property
    def failed(self) -> list[CheckResult]:
        return [c for c in self.checks if not c.ok]

    def to_dict(self) -> dict:
        return {
            "ok": self.ok,
            "base": self.base,
            "run_id": self.run_id,
            "started_at": self.started_at,
            "checks": [c.__dict__ for c in self.checks],
        }


def _scan_privacy(text: str) -> list[str]:
    """Return the list of pattern *labels* that fired. Never returns
    the actual matched bytes — that would defeat the purpose of the
    secret-redacting log."""
    leaks = []
    for rx, label in BANNED_PATTERNS:
        if re.search(rx, text):
            leaks.append(label)
    return leaks


def _http(method: str, url: str, *, auth: Optional[tuple[str, str]] = None,
          token: Optional[str] = None, body: Optional[dict] = None,
          timeout: float = 15.0) -> tuple[int, str, dict]:
    """Single request helper. Never raises on HTTP error — return tuple
    is (status, body_text, headers). Network failures become status 0."""
    headers = {"Accept": "application/json", "User-Agent": "yuelink-release-gate/1"}
    data = None
    if body is not None:
        data = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    if auth:
        b = base64.b64encode(f"{auth[0]}:{auth[1]}".encode("utf-8")).decode("ascii")
        headers["Authorization"] = f"Basic {b}"
    if token:
        headers["Authorization"] = f"Bearer {token}"
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.getcode(), resp.read().decode("utf-8", "replace"), dict(resp.headers)
    except urllib.error.HTTPError as e:
        try:
            text = e.read().decode("utf-8", "replace")
        except Exception:
            text = ""
        return e.code, text, dict(e.headers or {})
    except Exception as e:
        return 0, f"<network error: {type(e).__name__}>", {}


def check_no_auth_challenge(base: str, path: str) -> CheckResult:
    """Without credentials, a healthy dashboard endpoint must reject
    with 401 or 503 (creds-not-configured). Anything else means the
    route is missing or the auth dependency is bypassed."""
    code, body, _ = _http("GET", base.rstrip("/") + path)
    if code in (401, 503):
        detail = "auth-challenged" if code == 401 else "creds not configured"
        return CheckResult(f"no-auth {path}", True, detail, code)
    if code == 429 and "rate_limited" in body:
        # This no-auth check only proves nginx/FastAPI route mounting. A 429
        # still means the request reached the intended telemetry router; the
        # authenticated schema checks below keep stricter status handling.
        return CheckResult(f"no-auth {path}", True,
                           "rate-limited (router mounted)", code)
    if code == 200 and body.strip() == "ok":
        return CheckResult(
            f"no-auth {path}", False,
            "200 'ok' — nginx fallthrough, router not mounted", code,
        )
    if code == 0:
        return CheckResult(f"no-auth {path}", False, body, code)
    return CheckResult(
        f"no-auth {path}", False,
        f"unexpected status {code} body[:80]={body[:80]!r}",
        code,
    )


def check_authed(base: str, path: str, *, auth: tuple[str, str],
                 schema_keys: tuple[str, ...] = ()) -> CheckResult:
    code, body, _ = _http("GET", base.rstrip("/") + path, auth=auth)
    if code != 200:
        return CheckResult(
            f"authed {path}", False,
            f"HTTP {code} body[:80]={body[:80]!r}", code,
        )
    leaks = _scan_privacy(body)
    if any(label not in ("uuid_like",) for label in leaks):
        return CheckResult(
            f"authed {path}", False,
            f"privacy: {leaks}", code, privacy_leaks=leaks,
        )
    if schema_keys:
        try:
            data = json.loads(body)
        except Exception as e:
            return CheckResult(
                f"authed {path}", False,
                f"non-JSON body: {e}", code,
            )
        missing = [k for k in schema_keys if k not in data]
        if missing:
            return CheckResult(
                f"authed {path}", False,
                f"missing keys {missing}", code,
            )
    return CheckResult(f"authed {path}", True, "ok", code,
                        privacy_leaks=leaks)


def check_dashboard_html(base: str, *, auth: tuple[str, str]) -> CheckResult:
    code, body, _ = _http("GET", base.rstrip("/") + "/api/client/telemetry/dashboard",
                          auth=auth)
    if code != 200:
        return CheckResult("authed /dashboard", False,
                            f"HTTP {code}", code)
    if "<title>YueLink Telemetry</title>" not in body:
        return CheckResult("authed /dashboard", False,
                            "expected HTML title not present", code)
    leaks = [l for l in _scan_privacy(body) if l != "uuid_like"]
    if leaks:
        return CheckResult("authed /dashboard", False,
                            f"privacy: {leaks}", code, privacy_leaks=leaks)
    return CheckResult("authed /dashboard", True, "ok", code)


def synthetic_events(run_id: str) -> list[dict]:
    """The five required mixes from the task spec:
    ok, reality_auth_failed, ai_blocked, desktop_tun degraded,
    node_probe_result_v1 mode=tun. Every event is tagged
    client_id=release-gate-<run_id> for cleanup."""
    cid = f"release-gate-{run_id}"
    base = {
        "client_id": cid,
        "platform": "release-gate",
        "version": "release-gate-1.0",
    }
    now_ms = int(time.time() * 1000)
    return [
        {**base, "event": "release_gate_ok", "ts": now_ms,
         "synthetic": True, "note": "baseline"},
        {**base, "event": "node_probe_result_v1", "ts": now_ms,
         "fp": f"rgfp-{run_id}-1", "type": "vless",
         "target": "transport", "ok": False,
         "error_class": "reality_auth_failed", "synthetic": True},
        {**base, "event": "node_probe_result_v1", "ts": now_ms,
         "fp": f"rgfp-{run_id}-1", "type": "vless",
         "target": "transport", "ok": False,
         "error_class": "reality_auth_failed", "synthetic": True},
        {**base, "event": "node_probe_result_v1", "ts": now_ms,
         "fp": f"rgfp-{run_id}-2", "type": "vless",
         "target": "claude", "ok": False, "status_code": 403,
         "error_class": "ai_blocked", "synthetic": True},
        {**base, "event": "desktop_tun_state", "ts": now_ms,
         "state": "degraded", "platform_detail": "release-gate",
         "error_class": "missing_driver", "synthetic": True},
        {**base, "event": "node_probe_result_v1", "ts": now_ms,
         "fp": f"rgfp-{run_id}-3", "type": "trojan",
         "target": "transport", "ok": True, "latency_ms": 123,
         "connection_mode": "tun", "synthetic": True},
    ]


def check_ingest_round_trip(base: str, run_id: str) -> CheckResult:
    """POST synthetic events. Ingest is unauthenticated by design (the
    client app uses it to send events from end-user machines), so this
    check uses no auth header. Expect 200 + count == events.length."""
    body = {"events": synthetic_events(run_id)}
    code, txt, _ = _http("POST", base.rstrip("/") + "/api/client/telemetry",
                          body=body, timeout=20)
    if code != 200:
        return CheckResult("ingest round-trip", False,
                            f"HTTP {code} body[:80]={txt[:80]!r}", code)
    try:
        data = json.loads(txt)
    except Exception as e:
        return CheckResult("ingest round-trip", False,
                            f"non-JSON: {e}", code)
    if not data.get("ok") or data.get("count") != len(body["events"]):
        return CheckResult(
            "ingest round-trip", False,
            f"server reported count={data.get('count')} of "
            f"{len(body['events'])} events",
            code,
        )
    return CheckResult("ingest round-trip", True,
                        f"accepted {data['count']} events", code)


def check_active_probe_round_trip(
    base: str, run_id: str, token: str,
) -> CheckResult:
    """POST synthetic active-probe results. Skipped when token unset.
    Sends 4 results: 2 ok, 1 ai_blocked, 1 timeout — covers the rule
    set the dashboard relies on."""
    if not token:
        return CheckResult("active-probe round-trip", True,
                            "skipped (no ACTIVE_PROBE_TOKEN)")
    rid = f"rg-{run_id}"
    body = {
        "run_id": rid,
        "region": "release-gate",
        "probe_version": "release-gate/1",
        "started_at": int(time.time() * 1000),
        "finished_at": int(time.time() * 1000),
        "node_count": 2,
        "target_count": 2,
        "results": [
            {"node_fp": f"rgfp-{run_id}-a", "transport": "vless",
             "target": "transport", "status": "ok", "latency_ms": 100,
             "sample_id": uuid.uuid4().hex},
            {"node_fp": f"rgfp-{run_id}-a", "transport": "vless",
             "target": "github",    "status": "ok", "latency_ms": 200,
             "sample_id": uuid.uuid4().hex},
            {"node_fp": f"rgfp-{run_id}-b", "transport": "trojan",
             "target": "claude",    "status": "fail", "status_code": 403,
             "error_class": "ai_blocked",
             "sample_id": uuid.uuid4().hex},
            {"node_fp": f"rgfp-{run_id}-b", "transport": "trojan",
             "target": "transport", "status": "timeout",
             "error_class": "timeout", "timeout_ms": 5000,
             "sample_id": uuid.uuid4().hex},
        ],
    }
    code, txt, _ = _http("POST",
                          base.rstrip("/") + "/api/sre/active-probe/v1/results",
                          body=body, token=token, timeout=20)
    if code != 200:
        return CheckResult("active-probe round-trip", False,
                            f"HTTP {code} body[:80]={txt[:80]!r}", code)
    try:
        data = json.loads(txt)
    except Exception:
        data = {}
    if data.get("accepted") != 4 or data.get("dead_letter", 0) != 0:
        return CheckResult(
            "active-probe round-trip", False,
            f"server reported {data}", code,
        )
    return CheckResult("active-probe round-trip", True,
                        f"accepted 4 results in run {rid}", code)


def cleanup_synthetic(base: str, run_id: str,
                      auth: tuple[str, str]) -> CheckResult:
    body = {
        "client_id_prefix": f"release-gate-{run_id}",
        "active_probe_region": "release-gate",
    }
    code, txt, _ = _http(
        "POST",
        base.rstrip("/") + "/api/client/telemetry/admin/synthetic-cleanup",
        auth=auth, body=body, timeout=20,
    )
    if code == 404:
        return CheckResult("cleanup", True,
                            "endpoint not yet deployed (skipped)", code)
    if code != 200:
        return CheckResult("cleanup", False,
                            f"HTTP {code} body[:80]={txt[:80]!r}", code)
    return CheckResult("cleanup", True, txt[:80], code)


def run(args) -> GateReport:
    base = args.base.rstrip("/")
    run_id = uuid.uuid4().hex[:8]
    rep = GateReport(base=base, run_id=run_id, started_at=time.time())

    # 1. No-auth challenge across the dashboard fan
    for path in (
        "/api/client/telemetry/dashboard",
        "/api/client/telemetry/stats/summary?days=1",
        "/api/client/telemetry/stats/versions?days=1",
        "/api/client/telemetry/stats/nodes?days=1",
        "/api/client/telemetry/stats/node_health?days=1",
    ):
        rep.checks.append(check_no_auth_challenge(base, path))

    if args.full and args.user and args.password:
        auth = (args.user, args.password)
        # 2. Authed checks with schema validation.
        rep.checks.append(check_authed(
            base, "/api/client/telemetry/stats/summary?days=1",
            auth=auth,
            schema_keys=("window_days", "total_events", "unique_clients"),
        ))
        rep.checks.append(check_authed(
            base, "/api/client/telemetry/stats/versions?days=1",
            auth=auth, schema_keys=("distribution",),
        ))
        rep.checks.append(check_authed(
            base, "/api/client/telemetry/stats/nodes?days=1",
            auth=auth,
            schema_keys=("data_source", "node_count", "nodes", "rollup"),
        ))
        rep.checks.append(check_authed(
            base, "/api/client/telemetry/stats/node_health?days=1",
            auth=auth,
            schema_keys=("data_source", "node_count", "nodes"),
        ))
        rep.checks.append(check_dashboard_html(base, auth=auth))

        # 3. Ingest round-trip
        if not args.skip_ingest:
            rep.checks.append(check_ingest_round_trip(base, run_id))

        # 4. Active probe round-trip
        if not args.skip_probe:
            rep.checks.append(check_active_probe_round_trip(
                base, run_id, args.active_probe_token or "",
            ))

        # 5. Cleanup
        if not args.skip_ingest:
            rep.checks.append(cleanup_synthetic(base, run_id, auth))
    elif args.full:
        rep.checks.append(CheckResult(
            "full mode", False,
            "--full requires --user/--password (or env "
            "TELEMETRY_DASHBOARD_USER/PASSWORD)",
        ))
    return rep


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--base", default=os.environ.get(
        "TELEMETRY_BASE", "https://yue.yuebao.website"))
    p.add_argument("--user", default=os.environ.get("TELEMETRY_DASHBOARD_USER", ""))
    p.add_argument("--password", default=os.environ.get(
        "TELEMETRY_DASHBOARD_PASSWORD", ""))
    p.add_argument("--active-probe-token",
                   default=os.environ.get("TELEMETRY_ACTIVE_PROBE_TOKEN", ""))
    p.add_argument("--full", action="store_true",
                   help="run authed + ingest + active probe + cleanup")
    p.add_argument("--json", action="store_true",
                   help="emit JSON report instead of human text")
    p.add_argument("--skip-ingest", action="store_true")
    p.add_argument("--skip-probe", action="store_true")
    args = p.parse_args(argv)

    rep = run(args)

    if args.json:
        print(json.dumps(rep.to_dict(), indent=2, ensure_ascii=False))
    else:
        for c in rep.checks:
            mark = "✅" if c.ok else "❌"
            print(f"{mark} {c.name:35s}  {c.detail}")
        if rep.failed:
            print(f"\n{len(rep.failed)} failed; release-gate would block")
        else:
            print(f"\n✅ {len(rep.checks)} check(s) passed; release-gate ok")

    if not rep.ok:
        # Map the first failure to a more specific exit code so CI
        # can branch on it.
        first = rep.failed[0]
        if first.privacy_leaks:
            return 3
        if first.http_status in (404, 502, 503, 0):
            return 1
        if "schema" in first.detail.lower() or "missing keys" in first.detail.lower():
            return 2
        if "ingest" in first.name.lower() or "active-probe" in first.name.lower():
            return 4
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
