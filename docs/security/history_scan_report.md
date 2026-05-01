# Git history secret scan — 2026-05-01

Scope: full reachable git history. Tooling: `git log -G` + `git show` cross-checked
against `scripts/security_scan.sh --history`. All sensitive values below are
redacted to first-3-chars + last-1-char or replaced with `<redacted-…>`.

## Summary

| Severity | Count | Notes |
|---|---:|---|
| FAIL | 1 | Production Postgres password leaked in commit `bb5aada` (2026-04-15). Working tree was cleaned in subsequent commits, but the value remains in history. |
| NOTE | 0 | — |

This is a single-credential incident, scoped to one specific commit and
its immediate successors before the literal was removed.

## Confirmed leaks

### 1. `bb5aada` — Postgres DSN with literal password

- **Commit**: `bb5aada6608a60e0fbc67ec4421e2a29983158a3`
- **Date**: 2026-04-15 16:29:27 +0800
- **Author**: onesyue
- **Subject**: `feat(telemetry-server): migrate sqlite → PostgreSQL on yueops cluster`
- **Files affected** (added with literal):
  - `server/telemetry/telemetry.py` — `DEFAULT_DSN = "host=66.55.76.208 port=5432 user=root password=<redacted-prod-password> dbname=yueops"`
  - `server/telemetry/README.md` — env-var doc table example
  - systemd unit template (deployed from this commit)
  - `scripts/sre/deploy_telemetry_dashboard.sh` — referenced via env-var (no literal)

- **Credential type**: Postgres user / password
- **User**: `root`
- **Password**: `jim@…8` (12 chars, alphabetic + symbol + digit, low entropy)
- **Host**: `66.55.76.208:5432` — public-internet-reachable
- **Database**: `yueops` (shared with XBoard)

- **Privilege scope**: full user `root` on the cluster. Read/write
  to `yueops.*` including XBoard tables. **High blast radius.**

- **Remediation status (as of 2026-05-01)**:
  - ✅ Working tree no longer references the literal — `DSN = os.environ.get("TELEMETRY_DATABASE_DSN", "")` at `server/telemetry/telemetry.py:59`.
  - ✅ Repo defenses: `scripts/security_scan.sh` + `pre-commit` block re-introduction.
  - ❌ Credential **NOT** rotated. Anyone with the leaked commit can still connect as `root`.
  - ❌ History **NOT** rewritten. The leak is reachable via `git show bb5aada`.

- **Required follow-up**: `docs/security/credential_rotation_sop.md` step 2 (Postgres rotation).

### 2. `af597fa` — earlier reference to the same credential pattern

- **Commit**: `af597fa`
- **Date**: 2026-04-15 15:05:28 +0800 (same day as bb5aada)
- **Subject**: `feat(telemetry): 2026 UX roadmap phase 1 — flags, NPS, node events, health card`
- This commit predates `bb5aada` by ~1.5 hours and contains the same
  `host=66.55.76.208 … password=…` pattern in earlier draft form.
  Same credential, same leak. Treated as part of the same incident.

## Suspected-but-not-confirmed (NOTE-level)

`grep -G "DATABASE_URL"` in history returns only `bb5aada` and `af597fa`.
No other historic commit names a credential. The history scan also did not
surface:

- XBoard admin tokens
- Subscription URLs with embedded `token=`
- TLS private keys
- App signing keys
- iOS provisioning secrets

If a follow-up incident expands the scope, append a new section here with
date, commit, and the same fields as section 1.

## Reproducibility

Rerun the scan with:

```bash
bash scripts/security_scan.sh --history --json | jq '.findings[] | select(.severity=="FAIL")'
```

Expected output (as of 2026-05-01):

```json
{"rule":"prod_dsn","severity":"FAIL","file":"history@bb5aada","line":"server/telemetry/telemetry.py","match":"host=66.55…"}
{"rule":"historic_db_password","severity":"FAIL","file":"history@bb5aada","line":"server/telemetry/telemetry.py","match":"jim@…8"}
```

If new commits show up in the FAIL list, the SOP failed — escalate.

## Decision: do not rewrite history

Per `credential_rotation_sop.md` step 7. The repo is on GitHub; even
after `git filter-repo --force`, the old SHA remains cached for ~90
days and is widely mirrored. Rotation is the effective fix; history
rewrite is theatre.

The release-gate now **requires** that working-tree scan finds **zero**
FAIL findings before a tag is allowed to ship. History scan output is
informational only — it lives here, not in CI.
