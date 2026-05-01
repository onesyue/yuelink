# Credential rotation SOP

This SOP exists because on **2026-04-15** commit `bb5aada` committed a real
production Postgres DSN (`user=root password=<redacted-prod-password>`,
host `66.55.76.208:5432`, db `yueops`) into:

- `server/telemetry/telemetry.py` (as `DEFAULT_DSN` literal)
- `server/telemetry/README.md` (env-var docs)
- A systemd unit template

A subsequent commit removed the literal default and switched to
`os.environ.get("TELEMETRY_DATABASE_DSN", "")` — the working tree is
clean as of 2026-05-01 — but **the credential remains reachable in git
history**. Cloning the repo with full history exposes it.

The repo-side defenses (`scripts/security_scan.sh`, `pre-commit`,
release-gate) prevent this from happening again. They do **not** undo
the leak. The remaining work below is ops-only and cannot be performed
from a Claude Code session.

> **State of the rotation, as of 2026-05-01:**
> - ✅ repo defense: working tree clean, scanner + pre-commit + release-gate land in this PR
> - ✅ history scan: leak commit is `bb5aada`, password literal is recorded only in git history and redacted in working tree docs
> - ❌ **rotation: NOT DONE** — must be performed by ops with DB access
> - ❌ **history rewrite: NOT DONE** — decision pending

---

## 0. Pre-flight (5 min, anyone)

```bash
bash scripts/security_scan.sh                # working tree must be clean
bash scripts/security_scan.sh --history       # confirm bb5aada still has the literal
```

If `--history` shows new findings beyond `bb5aada`, **stop** and update
this SOP — the leak surface widened.

---

## 1. Identify affected credentials (10 min, ops)

| Credential | Host | First leaked | Last in HEAD | Status |
|---|---|---|---|---|
| Postgres `yueops` user `root`, password `<redacted-prod-password>` | `66.55.76.208:5432` | `bb5aada` (2026-04-15) | working tree clean since `bb5aada+1` | **MUST rotate** |
| `TELEMETRY_DASHBOARD_PASSWORD` | env-only | never literal | n/a | rotate as a precaution (cheap) |
| XBoard panel admin | `66.55.76.208:8001` | not leaked | n/a | not affected |
| Checkin API token | `23.80.91.14:8011` | not leaked | n/a | not affected |

The Postgres user is the only confirmed leak. The rest are listed for
audit completeness — do not skip the table on later incidents.

---

## 2. Rotate Postgres credential (15 min, ops with `psql` access to yueops)

The DB is on the same cluster as XBoard's `yueops` schema. Two safe options:

### Option A — Add new account, then revoke old (recommended)

```sql
-- as a superuser on the yueops cluster
CREATE ROLE telemetry_writer LOGIN PASSWORD '<openssl rand -base64 24>';
GRANT USAGE ON SCHEMA telemetry TO telemetry_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA telemetry TO telemetry_writer;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA telemetry TO telemetry_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO telemetry_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA telemetry
  GRANT USAGE ON SEQUENCES TO telemetry_writer;
```

If P7 / P5 tables (added in this same PR) exist, ensure they are owned
by or accessible to `telemetry_writer`:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON
  telemetry.node_state,
  telemetry.node_state_transitions,
  telemetry.node_state_reviews,
  telemetry.active_probe_runs,
  telemetry.active_probe_results,
  telemetry.active_probe_dead_letter
TO telemetry_writer;
```

Roll the new credential to systemd:

```bash
ssh ops@23.80.91.14
sudo install -m 0600 /dev/stdin /etc/checkin-api.env <<'EOF'
TELEMETRY_DATABASE_DSN=host=66.55.76.208 port=5432 user=telemetry_writer password=<new-password> dbname=yueops
TELEMETRY_DASHBOARD_USER=<unchanged>
TELEMETRY_DASHBOARD_PASSWORD=<rotated value, see step 3>
EOF
sudo systemctl restart checkin-api
```

Verify:

```bash
TELEMETRY_BASE=https://yue.yuebao.website python3 scripts/probe_telemetry.py --full \
  --user "$TELEMETRY_DASHBOARD_USER" --password "$TELEMETRY_DASHBOARD_PASSWORD"
```

Then revoke the old `root` access path:

```sql
-- ONLY after telemetry has been steady on telemetry_writer for ≥30 min
ALTER ROLE root WITH PASSWORD '<openssl rand -base64 32>';   -- random new value
-- Better still: revoke yueops access entirely if root was only used for telemetry.
```

### Option B — Rotate password on the existing user (fast, fewer audit benefits)

```sql
ALTER ROLE root WITH PASSWORD '<openssl rand -base64 24>';
```

Then update `/etc/checkin-api.env` and restart. This works but does
not give us a clean audit boundary — every other consumer of `root`
(if any) is also disrupted, and the audit log can't tell post-rotation
queries from pre-rotation ones.

> **Decision rule**: if `root` is only used by checkin-api / telemetry,
> Option B is fine. If anything else (XBoard, ops scripts, BI) connects
> as `root`, Option A is mandatory.

---

## 3. Rotate `TELEMETRY_DASHBOARD_PASSWORD` (5 min, ops)

This was never literal in the repo, but rotating now is cheap and
proves to the rest of the team that the SOP runs cleanly.

```bash
NEW_PASS="$(openssl rand -hex 16)"
ssh ops@23.80.91.14 "sudo sed -i 's/^TELEMETRY_DASHBOARD_PASSWORD=.*$/TELEMETRY_DASHBOARD_PASSWORD=${NEW_PASS}/' /etc/checkin-api.env && sudo systemctl restart checkin-api"
# Update GitHub Actions secret:
gh secret set TELEMETRY_DASHBOARD_PASSWORD --body "$NEW_PASS"
# Update memory note that records the dashboard creds (if used).
```

---

## 4. Verify old credential is dead (5 min, ops)

```bash
# Old DSN must NOT connect:
PGPASSWORD='<redacted-prod-password>' psql -h 66.55.76.208 -U root -d yueops -c '\q' \
  && echo "❌ OLD CREDENTIAL STILL WORKS — rotation incomplete" \
  || echo "✅ old credential rejected"
```

If the old credential still works, **stop**. The rotation has not
landed. Re-do steps 2–3.

---

## 5. Verify telemetry is alive on the new credential (5 min, ops)

```bash
# Synthetic round-trip via release-gate probe:
TELEMETRY_BASE=https://yue.yuebao.website \
TELEMETRY_DASHBOARD_USER=yuelink \
TELEMETRY_DASHBOARD_PASSWORD="$NEW_PASS" \
python3 scripts/probe_telemetry.py --full --json | jq .

# Expected: ok=true on all endpoints, no privacy_leaks.
```

Also confirm the `_extract_node_rows` ingest path works by checking
the dashboard `/stats/summary` for events from the last 5 min.

---

## 6. Synthetic data cleanup (3 min, ops)

The release-gate ingest test injects events with `client_id` like
`release-gate-<run_id>`. Clean them so they don't pollute prod stats:

```sql
DELETE FROM telemetry.events
 WHERE client_id LIKE 'release-gate-%'
   AND server_ts >= EXTRACT(EPOCH FROM now() - interval '7 days') * 1000;

DELETE FROM telemetry.active_probe_results
 WHERE region = 'release-gate';
DELETE FROM telemetry.active_probe_runs
 WHERE region = 'release-gate';
```

Or call the admin endpoint added in this PR:

```bash
curl -fsSu "$TELEMETRY_DASHBOARD_USER:$TELEMETRY_DASHBOARD_PASSWORD" \
  -X POST -d '{"client_id_prefix":"release-gate-"}' \
  -H 'Content-Type: application/json' \
  https://yue.yuebao.website/api/client/telemetry/admin/synthetic-cleanup
```

---

## 7. Decide on history rewrite (10 min, eng + ops)

This is **destructive** and rewrites every commit hash from `bb5aada`
forward. Don't do it without alignment.

Pros:
- The leaked password is no longer in any clone of the public repo.
- New contributors auditing the repo don't trip the scanner on history.

Cons:
- All forks / mirrors / cached CI checkouts diverge until they reset.
- Squashes the audit trail of how the issue was found and fixed.
- Old PR / issue links to commit hashes break.
- **GitHub still serves the old SHA from the cache for ~90 days** — if
  this repo is public, the leak is effectively permanent regardless.

**Default position**: do **not** rewrite history. Rotate the credential
(steps 1–4), document the leak in this SOP and the v1.1.x release
notes, and rely on the rotation being effective. The ROI on a forced
push is low because the credential is dead.

If you decide to rewrite anyway:

```bash
# ONLY on a host with full repo access. NEVER run this on a fork.
git clone --mirror git@github.com:<owner>/<repo>.git yuelink-mirror
cd yuelink-mirror
git filter-repo --replace-text <(echo '<redacted-prod-password>==>REDACTED')
git push --force --mirror
```

After force-push, every contributor must `git fetch --all && git reset
--hard origin/master`. Coordinate the window in chat first.

---

## 8. Record the rotation (5 min, eng)

Once steps 1–6 are done:

1. Append a row to the table at the top of this SOP — set the **Status**
   column to `rotated YYYY-MM-DD by <name>`.
2. Update the `feedback_no_auto_push.md` memory if applicable.
3. Note in the next release notes that a credential was rotated. Do
   **not** disclose the old password in release notes.

---

## 9. Final state assertions

The rotation is complete only when **all** of the following hold:

- [ ] Old `root@66.55.76.208:5432/yueops` credential rejects connections.
- [ ] `python3 scripts/probe_telemetry.py --full` reports `ok=true`.
- [ ] `bash scripts/security_scan.sh` returns `0` on working tree.
- [ ] `bash scripts/security_scan.sh --history` still finds `bb5aada`
      (expected — we did not rewrite) but **no new commits** include
      the credential.
- [ ] GitHub Actions `release-gate` workflow passes on a fresh tag.
- [ ] Release notes acknowledge the rotation (without disclosing the
      old or new credential).

Until every box is ticked, **report the rotation as IN-PROGRESS, not
DONE.** From the Claude Code session that produced this SOP, only the
working-tree defense and SOP itself are complete. Steps 2–9 are ops.
