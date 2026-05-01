#!/usr/bin/env python3
"""Reference single-region active probe runner.

Pairs with `server/telemetry/telemetry.py`'s P5 active-probe ingester.
This runner is intentionally minimal: ops can wrap it with cron, run it
in two regions, and start exporting RUM-vs-active-probe data without
waiting for a fancier service.

What it does:

  1. Reads a list of node fingerprints from a YAML file or stdin.
     The fingerprints are opaque tokens — server/uuid/password are NOT
     consumed by this runner. The privacy boundary is identical to
     `scripts/sre/probe_nodes.py`: only fp / type / region travel.
  2. For each (node_fp, target) pair, attempts an HTTP probe with a
     hard timeout. We don't actually connect through the node — the
     runner is the SRE's eye, not the user's. It records the outcome
     so the server can compare RUM (user-facing) against probe (our
     own measurement) and tell whether a 30% RUM dip is the node
     itself or someone's local ISP.
  3. POSTs the batch (or batches) to /api/sre/active-probe/v1/results
     using a bearer token from `--token` or `$ACTIVE_PROBE_TOKEN`.
  4. Writes a JSON report next to the node list for offline auditing.

Multi-region: each `--region` ID becomes its own run row in
`active_probe_runs`. Run the same script with `--region us-east-1` from
one host and `--region eu-west-1` from another. The dashboard can then
slice on region.

Usage:

    python3 scripts/sre/active_probe_runner.py \\
      --base https://yue.yuebao.website \\
      --region hk-1 \\
      --node-list nodes.yaml \\
      --json-output reports/probe-$(date -u +%Y%m%dT%H%M%SZ).json

    # Dry-run (no POST) — useful for first-time verification:
    python3 scripts/sre/active_probe_runner.py --dry-run --node-list nodes.yaml

Inputs (`nodes.yaml`):

    nodes:
      - fp: "abcdef0123"
        type: "vless"
      - fp: "fedcba9876"
        type: "trojan"

The runner does NOT pull fingerprints from XBoard or the server — that
keeps the runner stateless and scoped. Ops generates the list once per
release cycle and stores it next to the runner config.

Privacy check:

The runner refuses to read or emit any of the following field names:
  server, port, uuid, password, sni, public-key, short-id,
  Authorization, subscribe, token

If the input YAML contains any of those, the runner fails fast with a
non-zero exit.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "missing dep: PyYAML. install with `pip3 install pyyaml`. "
        "PyYAML is a runtime requirement, not a build dependency."
    )

PROBE_VERSION = "active_probe_runner.py/2026-05-01"

PROBE_TARGETS = {
    "transport": ("https://www.gstatic.com/generate_204", 200, 204),
    "google":    ("https://www.google.com/",              200, 399),
    "youtube":   ("https://www.youtube.com/",             200, 399),
    "netflix":   ("https://www.netflix.com/",             200, 399),
    "github":    ("https://api.github.com/",              200, 399),
    "claude":    ("https://claude.ai/",                   200, 399),
    "chatgpt":   ("https://chatgpt.com/",                 200, 399),
}

BANNED_FIELDS = (
    "server", "port", "uuid", "password", "passwd",
    "sni", "public-key", "publicKey", "short-id", "shortId",
    "authorization", "subscribe", "token",
)

CONNECT_TIMEOUT_SEC = 5
READ_TIMEOUT_SEC = 5


def assert_no_banned_fields(node: dict, source: str) -> None:
    for k in node.keys():
        if str(k).lower().replace("_", "-") in {b.lower() for b in BANNED_FIELDS}:
            sys.exit(f"refusing to read banned field {k!r} from {source}")


def load_nodes(path: str | None) -> list[dict]:
    if path == "-" or path is None:
        raw = yaml.safe_load(sys.stdin)
    else:
        raw = yaml.safe_load(Path(path).read_text(encoding="utf-8"))
    if not isinstance(raw, dict) or not isinstance(raw.get("nodes"), list):
        sys.exit("input YAML must be {nodes: [...]}")
    nodes = []
    for i, n in enumerate(raw["nodes"]):
        if not isinstance(n, dict):
            sys.exit(f"node #{i}: not a dict")
        assert_no_banned_fields(n, f"{path or '-'} #{i}")
        fp = (n.get("fp") or "").strip()
        if not fp:
            sys.exit(f"node #{i}: fp required")
        nodes.append({"fp": fp, "type": n.get("type") or None})
    return nodes


def probe_target(target: str, timeout_ms: int) -> dict:
    """Attempt the probe and classify the outcome.

    Status:
      ok       — HTTP status in expected range
      fail     — HTTP status outside range (e.g. 403, 502)
      timeout  — connect or read timeout
      error    — DNS / TLS / network error

    Latency is measured end-to-end. The runner does not retry; the
    server expects multiple samples per (node_fp, target) over time, so
    one timeout per cycle is fine."""
    if target not in PROBE_TARGETS:
        return {
            "target": target, "status": "error",
            "error_class": "unknown_target",
            "latency_ms": None, "status_code": None,
            "timeout_ms": timeout_ms,
        }
    url, lo, hi = PROBE_TARGETS[target]
    timeout_s = max(1.0, timeout_ms / 1000.0)
    started = time.monotonic()
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "yuelink-active-probe/1",
        })
        ctx = ssl.create_default_context()
        with urllib.request.urlopen(req, timeout=timeout_s, context=ctx) as resp:
            elapsed = int((time.monotonic() - started) * 1000)
            code = resp.getcode() or 0
            ok = lo <= code <= hi
            return {
                "target": target,
                "status": "ok" if ok else "fail",
                "status_code": code,
                "latency_ms": elapsed,
                "timeout_ms": timeout_ms,
                "error_class": None if ok else (
                    "ai_blocked" if (target in ("claude", "chatgpt")
                                     and code in (403, 429, 1020))
                    else f"http_{code}"
                ),
            }
    except urllib.error.HTTPError as e:
        elapsed = int((time.monotonic() - started) * 1000)
        # claude/chatgpt 403 / 1020 / 429 are CDN-rate-limit, not node failure
        is_ai = target in ("claude", "chatgpt")
        return {
            "target": target,
            "status": "fail",
            "status_code": e.code,
            "latency_ms": elapsed,
            "timeout_ms": timeout_ms,
            "error_class": "ai_blocked" if (is_ai and e.code in (403, 429, 1020))
            else f"http_{e.code}",
        }
    except (socket.timeout, urllib.error.URLError) as e:
        elapsed = int((time.monotonic() - started) * 1000)
        msg = str(e).lower()
        if "timed out" in msg or isinstance(e, socket.timeout):
            ec = "timeout"
            st = "timeout"
        elif "ssl" in msg or "tls" in msg or "handshake" in msg:
            ec = "tls_failed"
            st = "error"
        elif "dns" in msg or "name or service" in msg:
            ec = "dns_failed"
            st = "error"
        else:
            ec = "network_error"
            st = "error"
        return {
            "target": target, "status": st,
            "status_code": None, "latency_ms": elapsed,
            "timeout_ms": timeout_ms, "error_class": ec,
        }


def assert_response_no_secrets(payload: dict) -> None:
    """Defensive — should never fire. Asserts the runner output JSON
    has no banned JSON KEY names (not substrings — `port` matches
    `transport` if you don't anchor). This is a programming guard
    against later contributors adding 'server' / 'uuid' to result rows."""
    banned_lower = {b.lower() for b in BANNED_FIELDS}
    def walk(obj):
        if isinstance(obj, dict):
            for k, v in obj.items():
                if str(k).lower().replace("_", "-") in banned_lower:
                    raise RuntimeError(
                        f"runner produced banned key {k!r} — refusing to POST"
                    )
                walk(v)
        elif isinstance(obj, list):
            for item in obj:
                walk(item)
    walk(payload)


def post_results(base: str, token: str, body: dict, dry_run: bool) -> dict:
    if dry_run:
        return {"dry_run": True, "would_post_results": len(body["results"])}
    url = base.rstrip("/") + "/api/sre/active-probe/v1/results"
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {
            "ok": False,
            "http_status": e.code,
            "error": e.read().decode("utf-8", "replace")[:200],
        }
    except Exception as e:
        return {"ok": False, "error": str(e)[:200]}


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--base", default=os.environ.get(
        "TELEMETRY_BASE", "https://yue.yuebao.website"))
    p.add_argument("--token", default=os.environ.get("ACTIVE_PROBE_TOKEN", ""))
    p.add_argument("--region", required=True,
                   help="region tag — used for run row + dashboard slicing")
    p.add_argument("--node-list", help="path to YAML, or `-` for stdin")
    p.add_argument("--targets", default=",".join(PROBE_TARGETS.keys()),
                   help="comma-separated subset; default = all")
    p.add_argument("--timeout", type=int, default=5000,
                   help="per-target timeout in ms (default 5000)")
    p.add_argument("--batch-size", type=int, default=200,
                   help="max results per POST (default 200)")
    p.add_argument("--dry-run", action="store_true",
                   help="probe targets but do NOT POST")
    p.add_argument("--json-output", help="write JSON report to this path")
    args = p.parse_args(argv)

    if not args.dry_run and not args.token:
        sys.exit("--token (or ACTIVE_PROBE_TOKEN env var) is required without --dry-run")

    targets = [t.strip() for t in args.targets.split(",") if t.strip()]
    for t in targets:
        if t not in PROBE_TARGETS:
            sys.exit(f"unknown target: {t!r} (valid: {list(PROBE_TARGETS)})")

    nodes = load_nodes(args.node_list)
    run_id = f"run-{int(time.time())}-{uuid.uuid4().hex[:8]}"
    started_at = int(time.time() * 1000)

    # Probe loop. The runner doesn't actually go THROUGH each node —
    # YueLink's SRE goal here is to measure target-side reachability
    # from a known vantage point, then have the server compare it to
    # RUM. If we tried to dial through every node we'd need the user's
    # subscription, which is exactly the kind of secret we avoid.
    results: list[dict] = []
    for n in nodes:
        for tgt in targets:
            outcome = probe_target(tgt, args.timeout)
            outcome["node_fp"] = n["fp"]
            outcome["transport"] = n.get("type") or "unknown"
            outcome["sample_id"] = uuid.uuid4().hex
            results.append(outcome)

    finished_at = int(time.time() * 1000)
    print(f"  probed {len(nodes)} nodes × {len(targets)} targets "
          f"= {len(results)} results in "
          f"{(finished_at - started_at) / 1000:.1f}s")

    # Privacy guard before POSTing — never let a runner that was
    # extended later leak server/uuid/password downstream.
    assert_response_no_secrets({"results": results})

    # Send in batches so a single batch hitting the per-request limit
    # doesn't drop the entire run.
    posted = 0
    last_response: dict = {}
    for i in range(0, len(results), args.batch_size):
        batch = results[i:i + args.batch_size]
        body = {
            "run_id": run_id,
            "region": args.region,
            "probe_version": PROBE_VERSION,
            "started_at": started_at,
            "finished_at": finished_at,
            "node_count": len(nodes),
            "target_count": len(targets),
            "results": batch,
        }
        last_response = post_results(args.base, args.token, body, args.dry_run)
        posted += len(batch)
        if not args.dry_run and not last_response.get("ok", True):
            print(f"  ❌ POST failed at batch i={i}: {last_response}",
                  file=sys.stderr)
            break

    report = {
        "run_id": run_id,
        "region": args.region,
        "probe_version": PROBE_VERSION,
        "started_at": started_at,
        "finished_at": finished_at,
        "nodes": len(nodes),
        "targets": targets,
        "results_total": len(results),
        "results_posted": posted,
        "dry_run": args.dry_run,
        "last_server_response": last_response,
    }
    if args.json_output:
        Path(args.json_output).parent.mkdir(parents=True, exist_ok=True)
        Path(args.json_output).write_text(
            json.dumps(report, indent=2, ensure_ascii=False),
            encoding="utf-8",
        )
        print(f"  📝 wrote {args.json_output}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
