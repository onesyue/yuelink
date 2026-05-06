# YueLink Finalize Remaining Tasks — 2026-05-06 evening session

Continuation of `finalize-remaining-tasks-2026-05-06.md`. Closes the last
mainline punch list items: client telemetry path, server-side enrichment
extension, ECH/Secure-DNS regression fix, Sprint 2-A grayscale alignment,
DNS scheduler hardening, and a few SRE-discipline corrections to
mismeasured signals.

All work in this pass was performed against:

- Code repo: `onesyue/yuelink` branch `dev` (3 commits ahead of master)
- Yueops repo: `onesyue/yueops` branch `main` (1 commit ahead, push pending — server SSH key is read-only)
- XBoard host: `66.55.76.208` (postgres at `23.80.91.14`, web at `66.55.76.208` containers)
- Telemetry / DNS scheduler host: `23.80.91.14`

## TL;DR

| # | Item | State |
|---|---|---|
| 1 | ECH outer-SNI + browser Secure DNS routing fix (cf-fronted services on TUN) | ✅ shipped to repo + XBoard rules templates |
| 2 | Client `xb_server_id` field + path/asn/region/carrier aggregation | ✅ committed; awaiting v1.1.19 client release |
| 3 | Server enrichment: Cymru DNS **v4 + v6** + ASN→运营商 mapping (CT/CU/CM/EDU) + 1-step retry | ✅ deployed + verified |
| 4 | Sprint 2-A continuation: HY2 18-node bandwidth alignment + Stack/Giga group_id bump | ✅ DB committed |
| 5 | VLESS SNI second-pass deconcentration (max repeat 4 → 2) | ✅ DB committed |
| 6 | DNS scheduler: ALLOW_TW_ENABLE removed + TW relay dropped + cpu→load_score rename + back to dry-run | ✅ deployed |
| 7 | favicon.ico real ICO + CF cache purge | ✅ deployed |
| 8 | Three-relay "CPU 90%" misread corrected — actual CPU 7-28%, no procurement urgency | ✅ documented |

## 1. ECH outer-SNI + browser Secure DNS routing fix

### Problem
Browsers with Encrypted Client Hello + Secure DNS turned on couldn't load
ChatGPT / Claude under TUN mode while system-proxy was fine. Root cause:
every Cloudflare-fronted site shares `cloudflare-ech.com` as the outer
SNI; the sniffer rewrote `metadata.host` to that bare domain, sending the
TLS connection through the catch-all rule while the DoH probe and ECH
config fetch landed on yet another exit. Cloudflare saw inconsistent
client IPs across the DoH probe and the actual service connection and
served a JS challenge / hard-blocked. System-proxy mode hid the bug
because Chrome auto-disables Secure DNS when a system proxy is present.

### Fix (two complementary)

**Client** — committed to `dev` as `f2b443d`:

- `static_sections_transformer.dart` ensureSniffer — `cloudflare-ech.com`
  added to `skip-domain` so mihomo falls back to fake-ip reverse-lookup
  hostname (the real business domain) for ECH-wrapped TLS.
- `rules_transformer.dart` — new `ensureBrowserSecureDnsRules` injects
  cloudflare-dns / chrome.cloudflare-dns / mozilla.cloudflare-dns /
  dns.google / cloudflare-ech onto the same proxy group as the user's
  cf-fronted main service. Auto-detects the target group: AI-themed
  selects (AI / ChatGPT / OpenAI / Claude / Gemini, case-insensitive
  Latin-boundary regex) win first; otherwise GLOBAL / PROXY / AUTO /
  节点选择 / 🚀 / 手动切换 / 自动选择 / 全部节点; otherwise no-op.
- 9 unit tests + 3 goldens regenerated.

**Server** — XBoard rules templates on `66.55.76.208`:

- `app.clash.yaml` (yuelink-client subscription template) — sniffer
  skip-domain += cloudflare-ech.com; rules: prepended 5 DoH/ECH rules
  → AI; stripped `parse-pure-ip: true` and `force-dns-mapping: true`
  (the v1.0.21 P1-4 throughput killers, 30% regression on third-party
  Stash / clash-verge-rev / clash-party clients).
- `default.clash.yaml` (third-party clash template) — same.
- Backups: `*.bak-ech-fix-20260506-093853` × 2.
- Container cache cleared via `php artisan cache:clear`.

### Verification
- `flutter test` 960 pass / 0 fail across telemetry + golden + new ECH suite.
- `flutter analyze` clean.
- `scripts/check_imports.sh` passes the architecture import gate.
- Live `connections` table on the dev machine: `cloudflare-ech.com`,
  `cloudflare-dns.com`, `chrome.cloudflare-dns.com` now route via the
  AI exit alongside chatgpt.com (instead of falling into the catch-all
  Korean home-broadband node as they were).

## 2. Client telemetry: xb_server_id + per-node aggregation

Committed to `dev` as `6aa33b4` and `8010564`.

### Client (`lib/shared/node_telemetry.dart`)

- `node_probe_result_v1` event now emits `xb_server_id` when the
  inventory carries one. The server derives `path_class`
  (`direct / via_v4_relay / via_v6_relay`) from `xb_server_id`
  against `nodes-inventory-path-map.json` rather than guessing from
  `host=v4.yuetoto.net` (98 nodes share that hostname).
- Failure-probe rate limit: identical `(fp, target, error_class)`
  triples capped at 3 per 5-minute window to stop hard-failing nodes
  from flooding the events table.
- Existing test fixtures already had `'xb_server_id': 127` assertions;
  8/8 still passing.

### XBoard subscription side
Verified that XBoard `app/Protocols/ClashMeta.php` already injects
`xb_server_id` in 6 protocol blocks (vless / hysteria / trojan / ss /
…). Path is end-to-end intact pending v1.1.19 client release.

### Server aggregation (`server/telemetry/telemetry.py`)
- `_aggregate_v1_node_probe_rows` collects per-node Counter dicts:
  `xb_server_ids`, `path_classes`, `client_asns`, `client_countries`,
  `client_regions`, `client_carriers`.
- `_shape_node` outputs `top_xb_server_id`, `top_path_class`,
  `top_client_asn`, `top_client_carrier` plus full distributions.
- `_node_rollup` adds `by_path_class`, `by_client_asn`,
  `by_client_carrier` so the dashboard can answer "which path is
  healthier today" / "is this node only good for one carrier" without
  re-querying.

### Dashboard (`server/telemetry/dashboard.html`)
Carrier column inserted between ASN and Users; colspan bumped to 13.
Empty/unknown shows '—' so row width stays stable while CN traffic
ramps up under v1.1.18 users.

### Tests
17/17 server-side `test_stats_nodes_aggregation.py` pass; new
assertions cover `client_carrier='CT'/'CU'`, top_client_carrier,
client_carriers Counter, `by_client_carrier` rollup.

## 3. Server enrichment — IPv6 + ASN→运营商 + retry

Deployed to `23.80.91.14:/opt/checkin-api/main.py`.

Commits in production but not yet in any code repo (this Python lives
outside `onesyue/yuelink`; the patches were applied via a scripted
`sed`-style rewrite + .bak):

- `main.py.bak-cymru-v6-20260506-101554` — v6 path
- `main.py.bak-cymru-retry-20260506-112642` — retry + no-failure-cache

### v6 path (sentinel `# yuelink:cymru-v6+carrier`)
`_telemetry_client_context` no longer drops at `if addr.version != 4`.
`_cymru_qname(addr)` builds the right reverse name for each family:

- v4 → `<reversed octets>.origin.asn.cymru.com`
- v6 → `<reversed nibbles (32 of them)>.origin6.asn.cymru.com`

### CN carrier mapping
`_CN_CARRIER_ASN` dict maps 21 mainland ASNs to coarse carrier codes
when `cc=CN`:

- CT (China Telecom incl. CN2 GIA): 4134, 4812, 4811, 17621, 17816,
  23724, 9929, 4847, 23764
- CU (China Unicom): 4837, 4808, 17622
- CM (China Mobile): 9808, 56040, 24400, 134810, 137697, 9394, 56046,
  24445
- EDU (CERNET): 4538, 4565
- Anything else CN-routed → `CN_OTHER`

### Retry + no-failure-cache (sentinel `# yuelink:cymru-retry-no-failure-cache`)
Two-attempt loop with `+time=2 +tries=2` for each attempt and a 0.3 s
sleep between. Failed lookups deliberately skip the cache write — the
previous code locked an IP out of enrichment for 3600 s after a single
transient DNS failure; now the next request retries.

### In-process verification (post-restart)
```
114.114.114.114    → cc=CN asn=21859 carrier=CN_OTHER
117.50.10.10       → cc=CN asn=23724 carrier=CT
2408:8000:1010::1  → cc=CN asn=4808  carrier=CU      ← v6 path live
2606:4700:4700::1111 → cc=US asn=13335 (no carrier, non-CN)
1.1.1.1            → cc=AU asn=13335
```

## 4. Sprint 2-A continuation — HY2 bandwidth + plan group_id alignment

Backups: `v2_server_bak_hy2_bw_speed_limit_align_20260506`,
`v2_plan_bak_group_align_20260506`. Both single-tx commits.

### Node-level (v2_server, 18 hysteria rows)

| Old → New | Count | Aligns to plan |
|---|---|---|
| 500 → **1000** mbps | 4 (id 23, 25, 35, 39) | Max(1000) / Infinity(∞) |
| 400 → **800** mbps  | 7 (id 19, 20, 27, 29, 31, 37, 41) | Giga(800) |
| 300 → **500** mbps  | 4 (id 11, 12, 15, 16) | Pro(500) |
| 200 → **500** mbps  | 3 (id 7, 8, 33) | Pro(500) |

The 50 v4_relay HY2 nodes are zero-touch: they share HK/HK2/KR physical
egress (now confirmed at ~7-28 % CPU and 60-115 Mbps each, well below
saturation).

### Plan-level (v2_plan, 2 rows)

`Stack (id=6)` and `Giga (id=7)` moved from `group_id=1` to
`group_id=2`. They were classed as basic-tier alongside Mini / Air /
Travel even though their `speed_limit` (500 / 800) outranked Pro
(500). After the move:

| Plan | speed_limit | reachable HY2 1000 / 800 / 500 | total HY2 |
|---|---|---|---|
| Mini, Air, Travel  | 200 / 300 / 200 | 0 / 0 / 26 | 50 (v4_relay only) |
| Pro, Stack, Giga, Max, Infinity | 500 / 500 / 800 / 1000 / 0 | 4 / 7 / 33 | **70** |

So Max/Infinity can finally route through 1000 mbps nodes; Giga
through 800; Pro/Stack through 500 with headroom. No marketing copy
changed — only configuration was aligned to existing copy.

## 5. VLESS SNI second-pass deconcentration

Backup: `v2_server_bak_vless_sni_decon2_20260506`.

Top SNI repeat dropped from 4 to 2. 14 nodes touched, 4 SNIs
introduced into the rotation, all with `server_names=[new, old]`
dual-listing for compatibility during subscription refresh.

| 4-tuple before | After (split) |
|---|---|
| `www.amazon.com` × 4 | 2 keep amazon (老挝 147,148); 30 → www.epson.com; 40 → www.huawei.com |
| `www.philips.com` × 4 | 2 keep philips (荷兰 93,94); 183,184 → www.fedex.com |
| `www.siemens.com` × 4 | 2 keep siemens (新加坡 21,22); 89,90 → www.bosch.com |
| `www.panasonic.com` × 3 | 1 keeps panasonic (越南 36); 53,54 → www.toshiba.com |

Dual `server_names` count went from 20 → 24.

## 6. DNS scheduler hardening

Five changes on `23.80.91.14:/opt/yueops/scripts/dns-scheduler/scheduler.py`
and its systemd unit. All committed locally as `dab2f8f` on `main`,
push pending (server's deploy key is read-only).

1. `Environment=ALLOW_TW_ENABLE=1` removed from the systemd unit
   (was a residue from the TW reactivation experiment that left a
   live re-arm wire on the disk version of the unit).
2. `yue-tw-relay` removed from the `RELAYS` list — every 30 s tick
   was paying a ~6 s SSH probe to a host that the `is_tw_sid` guard
   already pinned to "noop". The DNS record for TW had been deleted
   out of band already.
3. `calc_health` return dict key `"cpu"` → `"load_score"`. The value
   is `100 - load/vcpu*100`, an inverse-load fitness score in
   `[0, 100]`. The "cpu" label caused a real-world misread:
   `cpu=91.2` was interpreted as "91 % CPU utilisation" and led to
   prioritising procurement when actual `vmstat us+sy` was 7-28 %.
4. ExecStart switched back from `--apply` to `--dry-run` per
   stated long-term preference: scheduler logs decisions but does
   not mutate DNS, until an explicit re-arm. With three v4 relays
   currently in-band the apply mode would have been a no-op anyway,
   but dry-run is the correct steady state.
5. `agent.sh` line 219 has its own `"cpu": $cpu` — that one IS true
   CPU utilisation from `top`/`sar`, deliberately untouched.

Verified next tick: `=== run start dry_run=True allow_tw_enable=False ===`,
all three relays decide `noop (in band)`, `changed=0`.

## 7. favicon.ico

`/home/nginx/conf.d/default.conf` `location = /favicon.ico` was
returning 43 bytes of `image/gif` (the `empty_gif` directive — a
heavy-handed anti-fingerprint that itself became a fingerprint
because real cf-fronted sites don't return image/gif as favicon).

Switched to a real multi-resolution ICO generated from
`assets/icon_desktop.png` (RGBA 1024×1024 → 16/32/48/64/128 px ICO,
18070 bytes, magic bytes `00 00 01 00`). Cloudflare cache for
`https://my.yue.to/favicon.ico` purged via the legacy
`X-Auth-Email` + `X-Auth-Key` API (zone `yue.to`).

Backups in `/home/nginx/conf.d/` and
`/home/xboard/yue-to/xboard-nginx/` with `*.bak-favicon-real-*`
suffix.

## 8. SRE-discipline corrections

The "three relays at 90 % CPU, procurement is the highest priority"
analysis from earlier in the session was wrong end-to-end:

- The 90 % was the scheduler's `cpu` field, which is actually
  `100 - load/vcpu*100` (a health score). The variable is renamed.
- `vmstat 1 2` on each host shows `us+sy`:
  - HK 209.9.201.127: 14 % (vCPU=6, load 0.53)
  - HK2 42.200.173.199: 7 % (vCPU=6, load 0.39)
  - KR 27.102.138.46: 28 % (vCPU=4, load 1.29 — relatively busiest)
- `/proc/net/dev` 2 s deltas:
  - HK ~65 Mbps in/out
  - HK2 ~61 Mbps in/out
  - KR ~115 Mbps in/out

Conclusion: HK and HK2 are nearly symmetric (no rebalancing needed);
all three have 8-15× headroom on a 1 Gbps uplink; the "采购优先级最高"
claim from the earlier note is retracted. KR's higher `sys%` (24 %)
deserves a follow-up look — it's still well below the danger zone but
suggests kernel-side IO that might benefit from sysctl / sing-box
tuning the next time we touch that host.

## Observation window

The advertised 48 h watch was compressed to 20 minutes per session
preference. During the window:

- `carrier_filled` events stayed at 0 — expected, opt-in telemetry
  is dominated by a small set of test users, no fresh CN-traffic
  cache miss landed in those 20 minutes. Enrichment path was
  in-process verified instead.
- HK/HK2/KR `Udp:` `RcvbufErrors` and `InErrors` counters showed
  zero delta across the entire 20 min — the earlier sysctl tuning
  is holding.
- `v4.yuetoto.net` resolved to the same three IPs across four public
  resolvers throughout — DNS state is stable.
- Scheduler kept printing `noop (in band)` → all three relays
  healthy.

## Rollback

| Layer | Backup | How to revert |
|---|---|---|
| Client repo | git history (`master..dev` is 3 commits) | `git revert f2b443d 6aa33b4 8010564` then push |
| XBoard rules | `/home/xboard/yue-to/rules/{app,default}.clash.yaml.bak-ech-fix-20260506-093853` | `mv` back, `php artisan cache:clear` |
| HY2 bandwidth | `v2_server_bak_hy2_bw_speed_limit_align_20260506` | `UPDATE … FROM bak WHERE id IN (…)` |
| Plan group_id | `v2_plan_bak_group_align_20260506` | same idiom |
| VLESS SNI | `v2_server_bak_vless_sni_decon2_20260506` | same |
| Server enrichment | `/opt/checkin-api/main.py.bak-cymru-v6-20260506-101554`, `*.bak-cymru-retry-20260506-112642` | `mv` + `systemctl restart checkin-api` |
| Server aggregator | `/opt/checkin-api/telemetry.py.bak-carrier-20260506-102813` | `mv` + restart |
| Dashboard | `/opt/checkin-api/dashboard.html.bak-carrier-20260506-102813` | `mv` |
| DNS scheduler unit | `/etc/systemd/system/yueops-dns-scheduler.service.bak-dryrun-*` | `mv`, `systemctl daemon-reload`, `systemctl restart yueops-dns-scheduler.timer` |
| nginx favicon | `/home/nginx/conf.d/default.conf.bak-favicon-*` (multiple) | `mv` + `docker exec nginx nginx -s reload` |

## Mainline backlog state after this pass

- ✅ TW DNS residue
- ✅ Verification (config + DB + sysctl + Loon patch + telemetry)
- ✅ Observation window (20 min, sysctl 0-error, DNS stable)
- 🔓 Path-class decision — unblocked once v1.1.19 ships and CN
  traffic surfaces (Cymru + carrier mapping is live; aggregator and
  dashboard already render the new dim)
- ✅ HK / TW SNI second batch (max repeat 4 → 2)
- ✅ HK / HK2 imbalance — turns out to be nominal (65 vs 61 Mbps)
- ❌ "三台 relay CPU 90%" item retracted; not a real problem
- ⏳ Procurement — no urgency. Three v4 relays have 8-15× headroom.

## Known not-done

- v1.1.19 client release tag — awaiting your call on timing. dev
  has 3 commits ahead of master, all reviewed in this session.
- Yueops repo push — server's deploy key is read-only; commit
  `dab2f8f` lives only on `23.80.91.14:/opt/yueops/.git`. Either
  upgrade the deploy key to write or pull-and-push from your
  local clone.
- GeoLite as Cymru fallback — explicitly deferred. Cymru +
  retry + no-failure-cache covers v4 + v6 in the verification suite;
  GeoLite would add a license-keyed dependency and a monthly mmdb
  refresh duty without clear marginal value.
- Sprint 2-A 48 h auto-monitor daemon — explicitly deferred. The
  three relays are healthy; an idle daemon would just produce
  noise. We can revive it if a real incident surfaces.
