#!/usr/bin/env python3
"""Black-box node probe — standardized success-rate measurement.

The thing we kept burning ourselves on during the 2026-05-01 incident: any
"30.1% success rate" number a person quoted in chat was untraceable —
nobody else could rerun it, the underlying URL/timeout/network/version
weren't recorded, and it spread anyway. This script exists so every
"success rate" we cite from now on points at a folder of artifacts that
anyone else can rerun and audit.

What it does:
  1. Parse a mihomo YAML config, list the nodes in the requested group.
  2. Launch a private mihomo subprocess on free ports (does not touch any
     running YueLink instance — its mixed-port and external-controller
     are overridden with random local ports).
  3. For each round, hit a 7-target matrix:
       transport · Claude · ChatGPT · Google · YouTube · Netflix · GitHub
     The 5 non-AI targets go through mihomo's /group/<g>/delay endpoint
     (concurrent, fast). Claude + ChatGPT need raw HTTP status codes
     (302 / 403 / 1020) so they go through a per-node selector switch
     + curl-through-mixed-port path on the FIRST round only by default.
  4. Emit artifacts:
       metadata.json          · test config + env + script version
       nodes_sanitized.json   · per-node hash + type + region (no secrets)
       samples.ndjson         · 1 line per (round, node, target) record
       summary.json           · per-node success rate, p50/p95/p99,
                                classification (healthy / node_down /
                                ai_blocked / path_mixed)
       mihomo.log             · mihomo stderr captured during run
       sanitization_audit.txt · final scan confirming no secrets leaked
  5. Audit: greps artifacts for verbatim copies of every server hostname,
     port, uuid, password, sni, public-key, short-id from the input YAML.
     Any hit fails the run (exit 4). This is the trip-wire that prevents
     a future schema change from quietly leaking secrets.

Usage:
  python3 scripts/sre/probe_nodes.py \\
    --config "$HOME/Library/Application Support/com.yueto.yuelink/yuelink.yaml" \\
    --mihomo ./macos/Frameworks/yuelink-mihomo \\
    --group "悦 · 自动选择" \\
    --rounds 5 --timeout-ms 5000 \\
    --out artifacts/probe-$(date -u +%Y%m%d-%H%M%SZ)
"""
from __future__ import annotations

import argparse
import contextlib
import hashlib
import http.client
import json
import os
import platform as _platform
import re
import secrets
import signal
import socket
import statistics
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit(
        "missing dep: PyYAML. install with `pip3 install pyyaml` "
        "(use the same Python that runs this script)"
    )

SCRIPT_VERSION = "probe_nodes.py/2026-05-01b"

# Name of the synthetic select group we inject into the temp mihomo
# config. Long + ugly so it cannot collide with anything a user / panel
# would name their group.
SYNTHETIC_GROUP = "__YUELINK_PROBE__"

# Domains we route through SYNTHETIC_GROUP via DOMAIN-SUFFIX rules. Real
# subscriptions usually have RULE-SET,openai,AI / RULE-SET,claude,AI /
# DOMAIN-SUFFIX,...,AI etc. — without rewriting the rules block, the
# AI-target raw HTTP path would keep flowing through the user's `AI`
# group regardless of which node we just switched the synthetic group
# to, mis-attributing every Claude/ChatGPT 403 to whichever proxy the
# `AI` group happened to select.
SYNTHETIC_RULE_DOMAINS = [
    # Claude / Anthropic
    "claude.ai", "anthropic.com",
    # OpenAI / ChatGPT
    "chatgpt.com", "openai.com", "oaistatic.com", "oaiusercontent.com",
    # Google + transport probe
    "google.com", "gstatic.com", "googleapis.com",
    # YouTube
    "youtube.com", "ytimg.com", "googlevideo.com",
    # Netflix
    "netflix.com", "nflxvideo.net", "nflximg.net", "nflxext.com",
    # GitHub
    "github.com", "githubusercontent.com",
]

# ── Target matrix ───────────────────────────────────────────────────────
# `kind="transport"` → mihomo /group/.../delay against generate_204
# `kind="content"`   → same, but landing page (treats any 2xx/3xx as ok)
# `kind="ai"`        → per-node selector switch + raw HTTP through
#                       mixed-port so we can read the actual status code
TARGETS = [
    ("transport", "transport", "https://www.gstatic.com/generate_204"),
    ("ai",        "claude",    "https://claude.ai/"),
    ("ai",        "chatgpt",   "https://chatgpt.com/"),
    ("transport", "google",    "https://www.google.com/generate_204"),
    ("transport", "youtube",   "https://www.youtube.com/generate_204"),
    ("content",   "netflix",   "https://www.netflix.com/"),
    ("content",   "github",    "https://github.com/"),
]
AI_TARGETS = [t for t in TARGETS if t[0] == "ai"]
NON_AI_TARGETS = [t for t in TARGETS if t[0] != "ai"]


# ── Sanitization ────────────────────────────────────────────────────────
# Fields that must NEVER appear in any artifact in plain text.
SECRET_KEYS = {
    "server", "port", "uuid", "password", "passwd",
    "sni", "servername", "server-name", "host",
    "public-key", "publickey", "short-id", "shortid",
    "path", "private-key", "auth", "psk", "alterId",
    "ws-opts", "http-opts", "grpc-opts", "h2-opts",
    "reality-opts", "reality",
}


def _stringify(v) -> str:
    if v is None:
        return ""
    return str(v)


def _node_fingerprint(p: dict) -> str:
    """Stable 16-hex hash. Same inputs as lib/shared/node_telemetry.dart
    so Dart and Python agree across pipelines."""
    parts = [
        _stringify(p.get("type")).lower().replace("hy2", "hysteria2"),
        _stringify(p.get("server")),
        _stringify(p.get("port")),
        _stringify(p.get("uuid") or p.get("password") or p.get("passwd")),
        _stringify(p.get("sni") or p.get("servername") or p.get("server-name") or p.get("host")),
        _stringify(p.get("node_id") or p.get("xb_server_id") or p.get("server_id") or ""),
    ]
    return hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()[:16]


_REGION_RULES = [
    (r"\b(hk|香港|港)\b|🇭🇰", "HK"),
    (r"\b(tw|台湾|台)\b|🇹🇼", "TW"),
    (r"\b(jp|日本|东京|大阪)\b|🇯🇵", "JP"),
    (r"\b(sg|新加坡|狮城)\b|🇸🇬", "SG"),
    (r"\b(us|美国|美西|美东|洛杉矶|纽约|圣何塞|硅谷)\b|🇺🇸", "US"),
    (r"\b(uk|英国|伦敦)\b|🇬🇧", "UK"),
    (r"\b(de|德国|法兰克福)\b|🇩🇪", "DE"),
    (r"\b(kr|韩国|首尔)\b|🇰🇷", "KR"),
    (r"\b(ca|加拿大)\b|🇨🇦", "CA"),
]


def _guess_region(name: str) -> str:
    lower = name.lower() if name else ""
    for pat, code in _REGION_RULES:
        if re.search(pat, lower):
            return code
    return "OTHER"


def _sanitize_node(p: dict, keep_label: bool) -> dict:
    fp = _node_fingerprint(p)
    name = _stringify(p.get("name"))
    return {
        "fp": fp,
        "type": _stringify(p.get("type")).lower().replace("hy2", "hysteria2"),
        "region": _guess_region(name),
        # label kept only when caller opts in; default off.
        "label": (name if keep_label else None),
    }


# ── YAML parsing ────────────────────────────────────────────────────────


def _load_proxies(config_path: Path) -> list[dict]:
    text = config_path.read_text(encoding="utf-8")
    doc = yaml.safe_load(text)
    if not isinstance(doc, dict):
        raise SystemExit("config does not parse as YAML mapping")
    proxies = doc.get("proxies")
    if not isinstance(proxies, list):
        raise SystemExit("config has no `proxies:` list")
    return [p for p in proxies if isinstance(p, dict)]


def _resolve_group_members(
    config_path: Path, group_name: str
) -> tuple[list[dict], list[str]]:
    """Return (full proxy list, names belonging to the requested group).

    If the group has nested references (proxies / use), they are flattened
    one level deep; not recursive — that's typically enough for url-test
    and selector groups.
    """
    text = config_path.read_text(encoding="utf-8")
    doc = yaml.safe_load(text)
    proxies = [p for p in doc.get("proxies", []) if isinstance(p, dict)]
    by_name = {p["name"]: p for p in proxies if "name" in p}

    groups = doc.get("proxy-groups", []) or []
    target_group = None
    for g in groups:
        if isinstance(g, dict) and g.get("name") == group_name:
            target_group = g
            break
    if target_group is None:
        # Fallback: probe every node in the config
        return proxies, [p["name"] for p in proxies if "name" in p]

    # Inline node names + flatten one level of nested groups
    names: list[str] = []
    for entry in target_group.get("proxies", []):
        if entry == "DIRECT" or entry == "REJECT":
            continue
        if entry in by_name:
            names.append(entry)
            continue
        # Nested group reference
        for g in groups:
            if isinstance(g, dict) and g.get("name") == entry:
                for child in g.get("proxies", []):
                    if child in by_name:
                        names.append(child)
                break
    # de-dupe preserving order
    seen: set[str] = set()
    deduped = []
    for n in names:
        if n in seen:
            continue
        seen.add(n)
        deduped.append(n)
    return proxies, deduped


# ── mihomo subprocess management ────────────────────────────────────────


def _free_port() -> int:
    with contextlib.closing(socket.socket(socket.AF_INET, socket.SOCK_STREAM)) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def _quote_reality_short_ids(config_text: str) -> str:
    """`yaml.safe_dump` round-trips Reality `short-id` values that came in
    as plain integers / unquoted hex without re-quoting them. mihomo's
    Reality parser refuses anything that isn't a string, so a config
    that loaded fine before our rewrite breaks on
    `proxy N: invalid REALITY short ID` after dump.

    The fix is mechanical and targeted: any line that looks like
    `<indent>short-id: <hex>` (no surrounding quotes) gets the value
    wrapped in single quotes. Anything that's already quoted, empty, or
    non-hex (which Reality short-id never is) is left alone.

    A safe_dump-time `Dumper` subclass would have been more elegant, but
    affects every string in the document — too much surface area for a
    one-symptom fix.
    """
    return re.sub(
        r"(?m)^(\s+short-id:\s+)(?!['\"])([0-9A-Fa-f]+)\s*$",
        r"\1'\2'",
        config_text,
    )


def _build_synthetic_rules() -> list[str]:
    """Minimal ruleset that pins every probe target — and everything else
    via MATCH — onto SYNTHETIC_GROUP. DOMAIN-SUFFIX rather than RULE-SET
    on purpose: keeps the temp config self-contained (no rule-providers
    to fetch)."""
    rules = [f"DOMAIN-SUFFIX,{d},{SYNTHETIC_GROUP}" for d in SYNTHETIC_RULE_DOMAINS]
    rules.append(f"MATCH,{SYNTHETIC_GROUP}")
    return rules


def _build_temp_config(
    src_yaml: Path,
    mixed_port: int,
    ext_port: int,
    secret: str,
    synthetic_members: list[str],
) -> str:
    """Build the temp mihomo config the probe runs against.

    Why we go through `yaml.safe_load → modify → safe_dump` instead of
    string surgery: we need to **append a synthetic select group AND
    replace the rules block**, and YAML's last-key-wins semantics for
    duplicate top-level keys would silently drop whichever rules block
    came first. A dump-based path is the only way to make sure mihomo
    sees exactly one `proxy-groups` and one `rules` key, both ours.

    Effects on top-level keys:
      mixed-port / external-controller / secret / log-level / allow-lan
                          → overwritten to probe-local values
      tun.enable          → forced false (probe runs unprivileged)
      proxy-groups        → user groups preserved + SYNTHETIC_GROUP
                            appended (so /group/<user_group>/delay still
                            works for the non-AI batch)
      rules               → replaced with seven-target DOMAIN-SUFFIX
                            rules + MATCH,SYNTHETIC_GROUP
      rule-providers      → dropped (nothing references them anymore)
    """
    text = src_yaml.read_text(encoding="utf-8")
    doc = yaml.safe_load(text) or {}
    if not isinstance(doc, dict):
        raise SystemExit("config does not parse as a YAML mapping")

    doc["mixed-port"] = mixed_port
    doc["external-controller"] = f"127.0.0.1:{ext_port}"
    doc["secret"] = secret
    doc["log-level"] = "info"
    doc["allow-lan"] = False
    if isinstance(doc.get("tun"), dict):
        doc["tun"]["enable"] = False

    groups = doc.get("proxy-groups")
    if not isinstance(groups, list):
        groups = []
    # Strip any pre-existing group with our reserved name (defensive —
    # user configs shouldn't have one, but if they do, ours wins).
    groups = [g for g in groups
              if not (isinstance(g, dict) and g.get("name") == SYNTHETIC_GROUP)]
    groups.append({
        "name": SYNTHETIC_GROUP,
        "type": "select",
        "proxies": list(synthetic_members),
    })
    doc["proxy-groups"] = groups

    doc["rules"] = _build_synthetic_rules()
    doc.pop("rule-providers", None)

    dumped = yaml.safe_dump(
        doc,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
    )
    return _quote_reality_short_ids(dumped)


@dataclass
class MihomoHandle:
    proc: subprocess.Popen
    log_path: Path
    ext_port: int
    mixed_port: int
    secret: str

    def base_url(self) -> str:
        return f"http://127.0.0.1:{self.ext_port}"

    def headers(self) -> dict:
        return {"Authorization": f"Bearer {self.secret}"}


def _start_mihomo(mihomo_bin: Path, cfg_path: Path, work_dir: Path,
                  log_path: Path, mixed_port: int, ext_port: int,
                  secret: str) -> MihomoHandle:
    """Caller owns writing cfg_path; this just launches the subprocess.
    Splitting the write from the launch lets [_validate_config] run
    `mihomo -t` against the same file before we open a long-running
    subprocess."""
    log_fh = log_path.open("w", encoding="utf-8")
    proc = subprocess.Popen(
        [str(mihomo_bin), "-d", str(work_dir), "-f", str(cfg_path)],
        stdout=log_fh, stderr=subprocess.STDOUT,
    )
    return MihomoHandle(
        proc=proc,
        log_path=log_path,
        ext_port=ext_port,
        mixed_port=mixed_port,
        secret=secret,
    )


def _validate_config(
    mihomo_bin: Path, cfg_path: Path, work_dir: Path,
) -> tuple[bool, str]:
    """Run `mihomo -t` for a config-only sanity check. Catches parse
    errors (Reality short-id validation, malformed YAML, missing
    referenced groups, …) without paying the 20s `/version` wait that
    `_wait_for_ready` would otherwise eat.

    Returns `(ok, output)`. Output captures stdout+stderr so failures
    can be surfaced verbatim to the operator — mihomo's error messages
    are usually precise enough to point at the offending proxy index.
    """
    try:
        proc = subprocess.run(
            [str(mihomo_bin), "-d", str(work_dir),
             "-f", str(cfg_path), "-t"],
            capture_output=True, text=True, timeout=15, errors="replace",
        )
    except subprocess.TimeoutExpired as e:
        return (False, f"mihomo -t timed out after {e.timeout}s")
    except FileNotFoundError as e:
        return (False, f"mihomo binary not executable: {e}")
    output = ((proc.stdout or "") + (proc.stderr or "")).strip()
    return (proc.returncode == 0, output)


def _wait_for_ready(h: MihomoHandle, timeout_s: float = 20.0) -> None:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        try:
            req = urllib.request.Request(h.base_url() + "/version", headers=h.headers())
            with urllib.request.urlopen(req, timeout=2) as resp:
                if resp.status == 200:
                    return
        except Exception:
            pass
        time.sleep(0.3)
    raise SystemExit("mihomo did not become reachable in time — see mihomo.log")


def _stop_mihomo(h: MihomoHandle) -> None:
    if h.proc.poll() is None:
        h.proc.send_signal(signal.SIGTERM)
        try:
            h.proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            h.proc.kill()
            h.proc.wait(timeout=5)


# ── Signal-driven cleanup ───────────────────────────────────────────────
#
# Without this, Ctrl-C mid-run leaves a mihomo subprocess holding
# ports + writing to a log fd we already orphaned. SIGTERM from a
# parent (CI, a wrapping shell script) has the same hazard. The
# handler is intentionally signal-safe — single-flag set + sys.exit
# from the registered Python frame, not from the signal handler
# itself, so atexit-registered teardown still runs.
_active_handle: "MihomoHandle | None" = None


def _set_active(h: "MihomoHandle | None") -> None:
    global _active_handle
    _active_handle = h


def _install_signal_handlers() -> None:
    def _bye(signum, _frame):
        h = _active_handle
        if h is not None:
            try:
                _stop_mihomo(h)
            except Exception:
                pass
        # Use the conventional exit code for terminate-by-signal so
        # callers / CI can distinguish "user cancelled" from "test
        # actually failed".
        sys.exit(128 + signum)

    signal.signal(signal.SIGINT, _bye)
    signal.signal(signal.SIGTERM, _bye)


def _redact_log(
    log_path: Path,
    name_to_fp: dict[str, str],
    secret_tokens: set[str],
) -> dict[str, int]:
    """Two-class scrub of mihomo.log:
      1. node labels  → `<node:FP>`  (so reports can still cross-reference
                                       which proxy a log line is about)
      2. secret tokens → `<secret>`  (server hostname / SNI / public-key /
                                       short-id / port / uuid / password
                                       — anything `_collect_secret_tokens`
                                       harvested from the YAML)

    Single ranked-by-length-desc sweep: a unified ordering is the only
    way to keep a 4-char hex short-id from accidentally erasing a
    substring inside a longer hostname before that hostname has had a
    chance to be matched. Empty / 1-char tokens are skipped because
    over-matching them would shred unrelated log content.

    Returns counts so `metadata.json` can record both numbers.
    Previously this function took `name_to_fp` but the caller passed
    `name_by_fp` (which is fp→name) — labels were never replaced. Fixed
    by giving the param a name that matches the call site contract.
    """
    if not log_path.exists():
        return {"labels": 0, "secrets": 0}
    text = log_path.read_text(encoding="utf-8", errors="ignore")

    # (token, replacement, kind). Single-character tokens dropped — they
    # would over-match common log noise.
    items: list[tuple[str, str, str]] = []
    for name, fp in name_to_fp.items():
        if name and len(name) >= 2:
            items.append((name, f"<node:{fp}>", "label"))
    for tok in secret_tokens:
        if tok and len(tok) >= 2:
            items.append((tok, "<secret>", "secret"))
    items.sort(key=lambda it: len(it[0]), reverse=True)

    label_count = 0
    secret_count = 0
    for token, repl, kind in items:
        new_text, n = re.subn(re.escape(token), repl, text)
        if n > 0:
            text = new_text
            if kind == "label":
                label_count += n
            else:
                secret_count += n
    log_path.write_text(text, encoding="utf-8")
    return {"labels": label_count, "secrets": secret_count}


# ── Probe primitives ────────────────────────────────────────────────────


def _api_get(h: MihomoHandle, path: str, timeout: float = 10.0) -> dict:
    url = h.base_url() + path
    req = urllib.request.Request(url, headers=h.headers())
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        body = resp.read().decode("utf-8")
    return json.loads(body) if body else {}


def _api_put(h: MihomoHandle, path: str, body: dict, timeout: float = 5.0) -> int:
    url = h.base_url() + path
    data = json.dumps(body).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, headers={**h.headers(), "Content-Type": "application/json"},
        method="PUT",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.status


def _group_delay(h: MihomoHandle, group: str, target_url: str, timeout_ms: int) -> dict:
    qs = urllib.parse.urlencode({"url": target_url, "timeout": timeout_ms})
    return _api_get(h, f"/group/{urllib.parse.quote(group)}/delay?{qs}",
                    # mihomo's /group/.../delay budget = round-trip per node.
                    # Budget on our side = nodes * timeout + slack.
                    timeout=max(30.0, timeout_ms / 1000 * 1.5 + 10.0))


def _raw_http_through_proxy(
    target_url: str, mixed_port: int, timeout_s: float
) -> tuple[bool, int | None, str | None, int | None]:
    """Issue a GET through the local mixed-port proxy and capture the
    response status code + latency. Used for AI sites where Cloudflare
    distinguishes 403 / 1020 / 302 — `/group/.../delay` collapses all of
    those to a single "fail".

    Returns `(ok, status_code, error_class, latency_ms)`.
      `ok` = True iff a final response was received (any 2xx/3xx/4xx/5xx).
      `latency_ms` = wallclock from CONNECT through final status read,
                     `None` on failure where no useful timing exists.
    """
    parsed = urllib.parse.urlparse(target_url)
    host = parsed.hostname
    if not host:
        return (False, None, "bad_url", None)
    port = parsed.port or (443 if parsed.scheme == "https" else 80)
    started = time.monotonic()
    try:
        # http.client.HTTPSConnection through a CONNECT tunnel is the
        # only stdlib way to bring a status code back from an HTTPS site
        # via an HTTP proxy without a third-party dep.
        conn = http.client.HTTPSConnection(
            "127.0.0.1", mixed_port, timeout=timeout_s,
        )
        conn.set_tunnel(host, port)
        conn.request("GET", parsed.path or "/", headers={
            "Host": host,
            "User-Agent": "yuelink-sre-probe/1.0",
            "Accept": "*/*",
        })
        resp = conn.getresponse()
        status = resp.status
        # Read & discard a small window so the connection cleans up.
        try:
            resp.read(2048)
        except Exception:
            pass
        conn.close()
        latency_ms = int((time.monotonic() - started) * 1000)
        # Any final-response status counts as "got through". The
        # classification step decides whether 403 means ai_blocked vs
        # healthy — that's not the probe's job.
        return (True, status, None, latency_ms)
    except socket.timeout:
        return (False, None, "timeout", None)
    except (ConnectionRefusedError, OSError) as e:
        return (False, None, f"socket:{type(e).__name__}", None)
    except http.client.HTTPException as e:
        return (False, None, f"http:{type(e).__name__}", None)
    except Exception as e:
        return (False, None, f"other:{type(e).__name__}", None)


def _switch_proxy(h: MihomoHandle, group: str, name: str) -> bool:
    try:
        return _api_put(h, f"/proxies/{urllib.parse.quote(group)}",
                        {"name": name}) in (200, 204)
    except Exception:
        return False


# ── Sample / summary types ──────────────────────────────────────────────


@dataclass
class Sample:
    round_no: int
    fp: str
    target: str
    ok: bool
    latency_ms: int | None
    error_class: str | None
    status_code: int | None

    def to_obj(self) -> dict:
        return {
            "round": self.round_no,
            "fp": self.fp,
            "target": self.target,
            "ok": self.ok,
            "latency_ms": self.latency_ms,
            "error_class": self.error_class,
            "status_code": self.status_code,
        }


def _classify_node(per_target: dict[str, dict]) -> str:
    """Decide healthy / node_down / ai_blocked / path_mixed.

    A target's success rate is `ok / attempted`. Thresholds picked
    intentionally loose so a single round can still surface a useful
    classification for the operator.
    """
    def succ(t):
        s = per_target.get(t)
        if not s or s["attempts"] == 0:
            return None
        return s["ok"] / s["attempts"]

    transport = succ("transport")
    google = succ("google")
    youtube = succ("youtube")
    github = succ("github")
    netflix = succ("netflix")
    claude = succ("claude")
    chatgpt = succ("chatgpt")

    rates = [r for r in (transport, google, youtube, github, netflix) if r is not None]
    if not rates:
        return "unknown"
    common_ok = statistics.mean(rates) >= 0.5
    ai_attempted = any(succ(t) is not None for t in ("claude", "chatgpt"))
    ai_ok = (
        (claude is not None and claude >= 0.5)
        or (chatgpt is not None and chatgpt >= 0.5)
    )

    if not common_ok:
        return "node_down"
    if ai_attempted and not ai_ok:
        return "ai_blocked"
    if common_ok and (not ai_attempted or ai_ok):
        return "healthy"
    return "path_mixed"


# ── Audit ───────────────────────────────────────────────────────────────


def _collect_secret_tokens(proxies: list[dict]) -> set[str]:
    """Scrape literal secret values from the input config so we can later
    confirm none appear in any artifact. Anything <4 chars is too noisy
    to be useful."""
    out: set[str] = set()
    def walk(v):
        if isinstance(v, dict):
            for k, vv in v.items():
                if k in SECRET_KEYS:
                    if isinstance(vv, (str, int)):
                        s = str(vv).strip()
                        if len(s) >= 4:
                            out.add(s)
                walk(vv)
        elif isinstance(v, list):
            for item in v:
                walk(item)
    for p in proxies:
        walk(p)
    return out


def _audit_artifacts(out_dir: Path, secret_tokens: set[str]) -> list[str]:
    """Grep every artifact for verbatim secrets. Returns a list of
    human-readable findings — empty list = clean."""
    findings: list[str] = []
    for f in sorted(out_dir.iterdir()):
        if not f.is_file() or f.name == "sanitization_audit.txt":
            continue
        try:
            text = f.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        for token in secret_tokens:
            if token in text:
                findings.append(f"{f.name}: contains secret token (len={len(token)})")
                break  # one finding per file is enough
    return findings


# ── Main flow ───────────────────────────────────────────────────────────


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", required=True, type=Path)
    ap.add_argument("--mihomo", required=True, type=Path)
    ap.add_argument("--group", default="GLOBAL",
                    help="proxy-group name (default: GLOBAL = every node)")
    ap.add_argument("--rounds", type=int, default=5)
    ap.add_argument("--timeout-ms", type=int, default=5000)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--keep-labels", action="store_true",
                    help="retain node `name` (label) in nodes_sanitized.json. "
                         "OFF by default — labels can leak region/server hints.")
    ap.add_argument("--ai-rounds", type=int, default=1,
                    help="how many rounds get the deep-probe (raw HTTP through "
                         "mixed-port) for Claude/ChatGPT status codes. "
                         "Higher = more accurate AI status distribution but "
                         "much longer wallclock. Default 1.")
    ap.add_argument("--max-ai-nodes", type=int, default=None,
                    help="cap how many nodes get the AI deep probe per round. "
                         "Default = all members. Subset is picked by "
                         "deterministic hash so reruns hit the same nodes — "
                         "useful for short SRE windows where you want a fast "
                         "AI sample (~50 nodes is usually enough to spot "
                         "ai_blocked patterns).")
    args = ap.parse_args()

    if not args.config.is_file():
        return _die(2, f"--config not found: {args.config}")
    if not args.mihomo.is_file():
        return _die(2, f"--mihomo not found: {args.mihomo}")
    args.out.mkdir(parents=True, exist_ok=True)

    _install_signal_handlers()

    proxies, group_names = _resolve_group_members(args.config, args.group)
    if not group_names:
        return _die(3, f"group '{args.group}' has no probe-able nodes")

    # Sanitized inventory. Note `name_by_fp` is intentionally
    # last-write-wins — we use it only for log redaction reverse-mapping
    # where any fp→name resolution suffices.
    inventory = []
    fp_by_name: dict[str, str] = {}
    name_by_fp: dict[str, str] = {}
    for p in proxies:
        if p.get("name") not in group_names:
            continue
        row = _sanitize_node(p, keep_label=args.keep_labels)
        inventory.append(row)
        fp_by_name[p["name"]] = row["fp"]
        name_by_fp[row["fp"]] = p["name"]

    secret_tokens = _collect_secret_tokens(
        [p for p in proxies if p.get("name") in group_names]
    )
    redaction_counts = {"labels": 0, "secrets": 0}

    # ── Mihomo lifecycle ────────────────────────────────────────────────
    mixed_port = _free_port()
    ext_port = _free_port()
    secret = secrets.token_hex(16)
    work_dir = Path(tempfile.mkdtemp(prefix="probe-mihomo-"))
    try:
        # Symlink geodata if available next to the source config.
        for asset in ("GeoIP.dat", "GeoSite.dat", "country.mmdb", "ASN.mmdb"):
            src = args.config.parent / asset
            if src.exists():
                try:
                    (work_dir / asset).symlink_to(src.resolve())
                except FileExistsError:
                    pass

        config_text = _build_temp_config(
            args.config, mixed_port, ext_port, secret,
            synthetic_members=group_names,
        )
        cfg_path = work_dir / "config.yaml"
        cfg_path.write_text(config_text, encoding="utf-8")

        # Pre-launch parse check. Beats waiting 20s on /version when the
        # actual problem was an unparseable YAML — `mihomo -t` exits in
        # under a second on success or with a precise error pointing at
        # the offending proxy index on failure.
        ok, validation_output = _validate_config(args.mihomo, cfg_path, work_dir)
        if not ok:
            print("❌ mihomo refused the temp config — see error below.",
                  file=sys.stderr)
            print(validation_output[:2000] or "(no output)", file=sys.stderr)
            (args.out / "mihomo_validate.txt").write_text(
                validation_output + "\n", encoding="utf-8")
            return 7

        log_path = args.out / "mihomo.log"
        h = _start_mihomo(args.mihomo, cfg_path, work_dir, log_path,
                          mixed_port, ext_port, secret)
        _set_active(h)
        try:
            _wait_for_ready(h)
            _run_probes(h, args, group_names, fp_by_name, name_by_fp, inventory)
        finally:
            _stop_mihomo(h)
            _set_active(None)
        # Redact AFTER mihomo flushes its log on shutdown so we catch
        # whatever it wrote during the final tick. Two classes need to
        # be scrubbed: human-readable labels (regional intel) AND any
        # YAML-scraped secrets that mihomo splattered into error
        # messages — Reality auth failures and DNS lookups freely
        # quote server hostnames + short-id values inline. Pass
        # `fp_by_name` (name → fp), NOT `name_by_fp` (fp → name) — the
        # function iterates the dict's keys as label candidates.
        redaction_counts = _redact_log(log_path, fp_by_name, secret_tokens)
    finally:
        # Don't leave the tmp config behind — even sanitized, the input
        # YAML lives there with original secrets.
        try:
            for child in work_dir.rglob("*"):
                if child.is_file():
                    child.unlink()
            work_dir.rmdir()
        except Exception:
            pass

    # Patch metadata with the redaction outcome (the run-time path didn't
    # know it yet when metadata was first written).
    meta_path = args.out / "metadata.json"
    try:
        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        meta["log_redaction"] = {
            "applied": (redaction_counts["labels"]
                        + redaction_counts["secrets"]) > 0,
            "label_replacements": redaction_counts["labels"],
            "secret_replacements": redaction_counts["secrets"],
            "scope": "node labels → <node:fp>; YAML-scraped secrets → <secret>",
        }
        meta_path.write_text(json.dumps(meta, indent=2, ensure_ascii=False),
                             encoding="utf-8")
    except Exception:
        pass

    # ── Final audit ─────────────────────────────────────────────────────
    findings = _audit_artifacts(args.out, secret_tokens)
    audit_path = args.out / "sanitization_audit.txt"
    if findings:
        audit_path.write_text(
            "FAILED\n" + "\n".join(findings) + "\n", encoding="utf-8")
        print(f"❌ sanitization audit failed — {len(findings)} hit(s)", file=sys.stderr)
        for f in findings:
            print(f"  {f}", file=sys.stderr)
        return 4
    audit_path.write_text(
        f"PASSED\nchecked tokens: {len(secret_tokens)}\n"
        f"artifacts scanned: {sum(1 for f in args.out.iterdir() if f.is_file())}\n",
        encoding="utf-8")
    print(f"✅ artifacts in {args.out}")
    return 0


def _die(code: int, msg: str) -> int:
    print(f"❌ {msg}", file=sys.stderr)
    return code


def _run_probes(
    h: MihomoHandle,
    args: argparse.Namespace,
    group_names: list[str],
    fp_by_name: dict[str, str],
    name_by_fp: dict[str, str],
    inventory: list[dict],
) -> None:
    started_at = datetime.now(timezone.utc)

    # Resolve mihomo's own version for metadata.
    try:
        version_info = _api_get(h, "/version", timeout=3.0)
        core_version = str(version_info.get("version", ""))
    except Exception:
        core_version = ""

    unique_fps = sorted({fp_by_name[n] for n in group_names if n in fp_by_name})

    metadata = {
        "script_version": SCRIPT_VERSION,
        "started_at_utc": started_at.isoformat(),
        "started_at_local_tz": time.strftime("%z"),
        "os": _platform.platform(),
        "python": sys.version.split()[0],
        "mihomo_path": str(args.mihomo),
        "mihomo_version": core_version,
        "config_path": str(args.config),
        "group": args.group,
        "synthetic_group": SYNTHETIC_GROUP,
        "synthetic_targets_routed": list(SYNTHETIC_RULE_DOMAINS),
        "rounds": args.rounds,
        "ai_rounds": args.ai_rounds,
        "timeout_ms": args.timeout_ms,
        # Two distinct counts: how many group entries the user's config
        # has (member_count) vs how many cryptographically distinct nodes
        # those entries cover (unique_fp_count). When they diverge, the
        # subscription has duplicate-named entries pointing at the same
        # underlying server — easy to mistake for "186 healthy" when the
        # data only supports a claim about ~119 distinct nodes.
        "member_count": len(group_names),
        "unique_fp_count": len(unique_fps),
        "targets": [{"kind": k, "name": n, "url": u} for k, n, u in TARGETS],
        "keep_labels": args.keep_labels,
        "log_redaction": {"applied": False, "replacements": 0,
                           "scope": "deferred until mihomo stops"},
    }
    (args.out / "metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8")
    (args.out / "nodes_sanitized.json").write_text(
        json.dumps({"count": len(inventory), "nodes": inventory},
                   indent=2, ensure_ascii=False), encoding="utf-8")

    samples_path = args.out / "samples.ndjson"
    samples_fh = samples_path.open("w", encoding="utf-8")
    all_samples: list[Sample] = []

    try:
        for round_no in range(1, args.rounds + 1):
            print(f"  round {round_no}/{args.rounds}…", flush=True)
            # 5 non-AI targets via /group/<SYNTHETIC>/delay. Using the
            # synthetic group rather than args.group keeps the script's
            # routing assumptions consistent: SYNTHETIC_GROUP contains
            # the same nodes (we just constructed it that way) and is
            # the only group whose state we mutate during AI rounds.
            for kind, t_name, t_url in NON_AI_TARGETS:
                try:
                    result = _group_delay(h, SYNTHETIC_GROUP, t_url,
                                          args.timeout_ms)
                except Exception as e:
                    print(f"    target={t_name} group_delay failed: {e}",
                          file=sys.stderr)
                    result = {}
                for node_name in group_names:
                    fp = fp_by_name.get(node_name)
                    if not fp:
                        continue
                    raw = result.get(node_name)
                    delay_ms = None
                    ok = False
                    err = None
                    if isinstance(raw, dict):
                        delay_ms = int(raw.get("delay") or 0) or None
                        ok = bool(delay_ms and delay_ms > 0)
                        if not ok:
                            err = (raw.get("message") or "timeout")[:80]
                    elif isinstance(raw, (int, float)):
                        delay_ms = int(raw)
                        ok = delay_ms > 0
                        err = None if ok else "timeout"
                    else:
                        err = "no_result"
                    s = Sample(round_no, fp, t_name, ok, delay_ms, err, None)
                    all_samples.append(s)
                    samples_fh.write(json.dumps(s.to_obj(),
                                                ensure_ascii=False) + "\n")

            # AI targets — only on first --ai-rounds rounds. Switch
            # SYNTHETIC_GROUP (NOT the user's group): the temp config's
            # `MATCH,SYNTHETIC_GROUP` rule + DOMAIN-SUFFIX,claude.ai,
            # SYNTHETIC_GROUP is what makes the per-node selector
            # change actually affect Claude/ChatGPT traffic. Switching
            # the user's `悦 · 自动选择` here would be a no-op for AI
            # routing as long as the original RULE-SET,openai,AI rule
            # was kept — which is exactly the bug that got us here.
            if round_no <= args.ai_rounds:
                # Deterministic hash sample so reruns hit the same nodes.
                # Random sampling would produce different results each run
                # and make incident triage harder ("which nodes did I
                # actually probe last time?"). The hash key is the only
                # part that's exposed to the operator's choice — change
                # the seed by renaming nodes.
                ai_node_subset = group_names
                if args.max_ai_nodes and len(group_names) > args.max_ai_nodes:
                    ai_node_subset = sorted(
                        group_names,
                        key=lambda n: hashlib.sha256(n.encode("utf-8")).hexdigest(),
                    )[:args.max_ai_nodes]
                    print(f"    AI deep-probe sampled "
                          f"{len(ai_node_subset)}/{len(group_names)} nodes "
                          f"(--max-ai-nodes={args.max_ai_nodes})", flush=True)
                for kind, t_name, t_url in AI_TARGETS:
                    for node_name in ai_node_subset:
                        fp = fp_by_name.get(node_name)
                        if not fp:
                            continue
                        if not _switch_proxy(h, SYNTHETIC_GROUP, node_name):
                            s = Sample(round_no, fp, t_name, False, None,
                                       "switch_failed", None)
                        else:
                            # Brief settle so the selector switch has
                            # actually propagated to mihomo's dialer
                            # before we open a new HTTP connection.
                            time.sleep(0.05)
                            ok, status, err, latency_ms = (
                                _raw_http_through_proxy(
                                    t_url, h.mixed_port,
                                    args.timeout_ms / 1000,
                                )
                            )
                            s = Sample(round_no, fp, t_name, ok, latency_ms,
                                       err, status)
                        all_samples.append(s)
                        samples_fh.write(json.dumps(s.to_obj(),
                                                    ensure_ascii=False) + "\n")
            else:
                print(f"    AI targets skipped (ai_rounds={args.ai_rounds})",
                      flush=True)
    finally:
        samples_fh.close()

    # ── Summary ─────────────────────────────────────────────────────────
    by_fp: dict[str, dict] = {row["fp"]: {
        "fp": row["fp"], "type": row["type"], "region": row["region"],
        "label": row.get("label"),
        "per_target": {},
    } for row in inventory}

    for s in all_samples:
        node = by_fp.get(s.fp)
        if node is None:
            continue
        t = node["per_target"].setdefault(s.target, {
            "attempts": 0, "ok": 0, "latencies": [],
            "errors": {}, "statuses": {},
        })
        t["attempts"] += 1
        if s.ok:
            t["ok"] += 1
            if s.latency_ms:
                t["latencies"].append(s.latency_ms)
        if s.error_class:
            t["errors"][s.error_class] = t["errors"].get(s.error_class, 0) + 1
        if s.status_code is not None:
            key = str(s.status_code)
            t["statuses"][key] = t["statuses"].get(key, 0) + 1

    # Each fp may correspond to >1 group member. We expose the count so
    # the operator can decide whether to weight a bucket "by member"
    # (which doubles a duplicate node) or "by fp" (which doesn't). The
    # member names list is intentionally NOT included unless --keep-labels
    # was passed, since labels can leak region info.
    members_by_fp: dict[str, list[str]] = {}
    for n in group_names:
        fp = fp_by_name.get(n)
        if fp is None:
            continue
        members_by_fp.setdefault(fp, []).append(n)

    summary_nodes = []
    fp_to_classification: dict[str, str] = {}
    for fp, node in by_fp.items():
        per_target_out = {}
        for t_name, t in node["per_target"].items():
            lats = sorted(t["latencies"])
            def pct(p):
                if not lats:
                    return None
                idx = max(0, min(len(lats) - 1, int(round(p * (len(lats) - 1)))))
                return lats[idx]
            per_target_out[t_name] = {
                "attempts": t["attempts"],
                "ok": t["ok"],
                "success_rate": (t["ok"] / t["attempts"]) if t["attempts"] else None,
                "p50_ms": pct(0.50),
                "p95_ms": pct(0.95),
                "p99_ms": pct(0.99),
                "errors": t["errors"],
                "statuses": t["statuses"],
            }
        cls = _classify_node(node["per_target"])
        fp_to_classification[fp] = cls
        node_out = {
            "fp": fp,
            "type": node["type"],
            "region": node["region"],
            "classification": cls,
            "member_count": len(members_by_fp.get(fp, [])),
            "per_target": per_target_out,
        }
        if node["label"]:
            node_out["label"] = node["label"]
        if args.keep_labels:
            node_out["member_labels"] = members_by_fp.get(fp, [])
        summary_nodes.append(node_out)

    # Two-axis classification rollup. by_fp counts each unique node once;
    # by_member counts each entry in the user's group, so duplicate-named
    # nodes pointing at the same underlying server are counted N times.
    # Operators almost always want by_fp for "node pool health" and
    # by_member for "what fraction of the user's group is healthy".
    buckets_by_fp = {"healthy": 0, "node_down": 0, "ai_blocked": 0,
                     "path_mixed": 0, "unknown": 0}
    for n in summary_nodes:
        buckets_by_fp[n["classification"]] = buckets_by_fp.get(
            n["classification"], 0) + 1

    buckets_by_member = {"healthy": 0, "node_down": 0, "ai_blocked": 0,
                         "path_mixed": 0, "unknown": 0}
    for member_name in group_names:
        fp = fp_by_name.get(member_name)
        cls = fp_to_classification.get(fp, "unknown") if fp else "unknown"
        buckets_by_member[cls] = buckets_by_member.get(cls, 0) + 1

    overall_attempts = len(all_samples)
    overall_ok = sum(1 for s in all_samples if s.ok)
    summary = {
        "started_at_utc": started_at.isoformat(),
        "finished_at_utc": datetime.now(timezone.utc).isoformat(),
        "rounds": args.rounds,
        # Both counts surfaced at the top level so a casual reader sees
        # them before the per-fp detail. Don't drop either.
        "member_count": len(group_names),
        "unique_fp_count": len(unique_fps),
        "samples_total": overall_attempts,
        "samples_ok": overall_ok,
        "overall_success_rate": (overall_ok / overall_attempts)
                                  if overall_attempts else None,
        "classification_buckets_by_fp": buckets_by_fp,
        "classification_buckets_by_member": buckets_by_member,
        "nodes": summary_nodes,
    }
    (args.out / "summary.json").write_text(
        json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    pct_overall = (overall_ok / overall_attempts * 100) if overall_attempts else 0
    print(
        f"  samples: {overall_ok}/{overall_attempts} ({pct_overall:.1f}%) "
        f"members={len(group_names)} unique_fps={len(unique_fps)} "
        f"by_fp={buckets_by_fp} by_member={buckets_by_member}"
    )


if __name__ == "__main__":
    sys.exit(main())
