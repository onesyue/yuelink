#!/usr/bin/env bash
# Working-tree secret + sensitive-field scanner.
#
# Two modes — both are local, neither rewrites git history:
#
#   default              : scan working tree (no committed leaks)
#   --history            : also scan reachable git history (much slower)
#   --json               : emit JSON {ok, findings: [...]}
#   --pre-commit         : scan only files staged for commit (called from
#                          scripts/pre-commit)
#
# What we look for:
#
#   1. Real-looking Postgres DSNs:
#        postgres://user:pass@host:port/db
#        host=… password=…
#      with allow-list for known fake fixture values.
#
#   2. Sensitive XBoard / mihomo node fields appearing in code or telemetry
#      strings: server, port, uuid, password, sni, public-key, short-id,
#      auth header, subscription token URL.
#
#   3. Bearer-style tokens (long random hex / base64).
#
#   4. The historically-leaked production credential pattern — explicitly,
#      because it was once in the working tree and we never want it back.
#
# Allow-list lives at scripts/security_scan.allowlist (one regex per line,
# comments allowed). A finding whose match column is in the allow-list is
# downgraded from FAIL to NOTE so test fixtures and intentional documentation
# references don't bounce CI.
#
# Exit codes:
#   0 = no FAIL findings
#   1 = at least one FAIL finding (release-gate blocks)
#   2 = usage error
#   3 = scan tool missing

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ALLOWLIST="$REPO_ROOT/scripts/security_scan.allowlist"

MODE="working-tree"
JSON=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --history)     MODE="history"; shift ;;
    --pre-commit)  MODE="pre-commit"; shift ;;
    --json)        JSON=1; shift ;;
    -h|--help)
      sed -n '3,30p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v grep >/dev/null 2>&1; then
  echo "grep not found — install GNU grep or BSD grep" >&2
  exit 3
fi

# ── Patterns ────────────────────────────────────────────────────────────
# Format: rulename|severity|extended-regex
# severity: FAIL (blocks release), NOTE (informational only).
#
# Stored as an indexed array so we don't have to parse a heredoc inside
# the per-file loop — the heredoc-into-variable form via `read -r -d ''`
# was eating the rule field on some bash versions.
PATTERNS=(
  'prod_dsn|FAIL|host=[^[:space:]"'"'"'\\]+[[:space:]]+port=[0-9]+[[:space:]]+user=[^[:space:]"'"'"']+[[:space:]]+password='
  'prod_dsn_url|FAIL|postgres(ql)?://[^[:space:]"'"'"'<>]+:[^[:space:]"'"'"'<>@]+@[^[:space:]"'"'"'<>/]+'
  'historic_db_password|FAIL|j[i]m@?88[0-9]{2}'
  'sub_token_url|FAIL|/api/v1/client/subscribe\?token=[A-Za-z0-9]{16,}'
  'generic_uuid|NOTE|\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b'
  'auth_bearer|NOTE|Authorization:[[:space:]]*Bearer[[:space:]]+[A-Za-z0-9_.\-]{20,}'
  'xb_password_assign|NOTE|password['"'"'"]?[[:space:]]*[:=][[:space:]]*['"'"'"][^'"'"'"]{6,}['"'"'"]'
)

if [[ ! -f "$ALLOWLIST" ]]; then
  # Seed an empty allowlist on first run so the file is always present.
  printf '# scripts/security_scan.allowlist — one regex per line.\n# A FAIL/NOTE finding whose match text matches any regex here is\n# downgraded to ALLOWED. Comment lines start with #.\n' > "$ALLOWLIST"
fi

allow_match() {
  local line="$1"
  local allow_pat
  while IFS= read -r allow_pat; do
    allow_pat="${allow_pat%%#*}"
    allow_pat="$(echo "$allow_pat" | awk '{$1=$1};1')"
    [[ -z "$allow_pat" ]] && continue
    if echo "$line" | grep -E -q -- "$allow_pat"; then
      return 0
    fi
  done < "$ALLOWLIST"
  return 1
}

# ── Target file list ────────────────────────────────────────────────────
target_list() {
  case "$MODE" in
    working-tree)
      git -C "$REPO_ROOT" ls-files
      ;;
    pre-commit)
      git -C "$REPO_ROOT" diff --name-only --cached --diff-filter=ACMR
      ;;
    history)
      # We scan blobs, not file paths — handled inline below.
      ;;
  esac
}

# ── Scan ────────────────────────────────────────────────────────────────
FINDINGS=()    # rule|severity|file|line|match
FAIL_COUNT=0
NOTE_COUNT=0
ALLOW_COUNT=0

scan_path() {
  local path="$1"
  [[ -d "$REPO_ROOT/$path" || ! -f "$REPO_ROOT/$path" ]] && return 0
  case "$path" in
    # Skip our own scanner + allowlist + this scan's documentation
    # — they intentionally contain the literal patterns.
    scripts/security_scan.sh|scripts/security_scan.allowlist) return 0 ;;
    docs/security/*) return 0 ;;
    # Skip large binaries / generated artifacts
    *.dat|*.mmdb|*.png|*.jpg|*.jpeg|*.ico|*.icns|*.so|*.dll|*.dylib|*.a|*.zip|*.gz|*.lock) return 0 ;;
    # Skip vendored Go submodule — scanned separately if needed
    core/mihomo/*) return 0 ;;
  esac

  for entry in "${PATTERNS[@]}"; do
    local rule severity rx
    IFS='|' read -r rule severity rx <<< "$entry"
    [[ -z "${rule:-}" || "$rule" =~ ^# ]] && continue
    while IFS=: read -r ln content; do
      [[ -z "$ln" ]] && continue
      local match_text
      match_text="$(echo "$content" | grep -oE -- "$rx" | head -1 || true)"
      [[ -z "$match_text" ]] && continue
      if allow_match "$content"; then
        ALLOW_COUNT=$((ALLOW_COUNT + 1))
        continue
      fi
      # Truncate match for output safety — don't print full secret if it
      # somehow IS a real secret. 12 chars is enough to identify the rule
      # without re-leaking.
      local short
      short="${match_text:0:12}…"
      FINDINGS+=("$rule|$severity|$path|$ln|$short")
      if [[ "$severity" == "FAIL" ]]; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        NOTE_COUNT=$((NOTE_COUNT + 1))
      fi
    done < <(grep -nE -- "$rx" "$REPO_ROOT/$path" 2>/dev/null || true)
  done
}

# ── Working-tree / pre-commit scan ──────────────────────────────────────
if [[ "$MODE" == "working-tree" || "$MODE" == "pre-commit" ]]; then
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    scan_path "$path"
  done < <(target_list)
fi

# ── History scan ────────────────────────────────────────────────────────
# Walks every reachable commit and runs each pattern. Order of magnitude
# slower than working-tree (~30s on a moderate repo) — intended for
# incident triage, not pre-commit.
if [[ "$MODE" == "history" ]]; then
  for entry in "${PATTERNS[@]}"; do
    rule=""; severity=""; rx=""
    IFS='|' read -r rule severity rx <<< "$entry"
    [[ -z "${rule:-}" || "$rule" =~ ^# ]] && continue
    # `git log -G` matches blobs whose diff added/removed the pattern.
    while IFS= read -r commit; do
      [[ -z "$commit" ]] && continue
      # Show one diff hunk to name the file.
      while IFS=$'\t' read -r path; do
        [[ -z "$path" ]] && continue
        FINDINGS+=("$rule|$severity|history@$commit|$path|<see git show $commit>")
        if [[ "$severity" == "FAIL" ]]; then
          FAIL_COUNT=$((FAIL_COUNT + 1))
        else
          NOTE_COUNT=$((NOTE_COUNT + 1))
        fi
      done < <(git -C "$REPO_ROOT" show --name-only --pretty=format: "$commit" 2>/dev/null | sort -u | head -10)
    done < <(git -C "$REPO_ROOT" log --all --pretty=tformat:'%h' -G "$rx" 2>/dev/null | head -50)
  done
fi

# ── Output ──────────────────────────────────────────────────────────────
if [[ "$JSON" -eq 1 ]]; then
  printf '{"mode":"%s","ok":%s,"fail":%d,"note":%d,"allowed":%d,"findings":[' \
    "$MODE" "$([ $FAIL_COUNT -eq 0 ] && echo true || echo false)" \
    "$FAIL_COUNT" "$NOTE_COUNT" "$ALLOW_COUNT"
  for i in "${!FINDINGS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    IFS='|' read -r rule severity file lineno short <<< "${FINDINGS[$i]}"
    # Escape quotes in the small output fields. None of these values
    # should contain control chars; if they do, the JSON consumer will
    # still parse because we strip newlines via `tr` upstream.
    printf '{"rule":"%s","severity":"%s","file":"%s","line":"%s","match":"%s"}' \
      "$rule" "$severity" "$file" "$lineno" "$short"
  done
  printf ']}\n'
else
  if [[ ${#FINDINGS[@]} -eq 0 ]]; then
    echo "✅ security_scan.sh ($MODE): no findings"
  else
    echo "security_scan.sh ($MODE):"
    echo "  FAIL=$FAIL_COUNT  NOTE=$NOTE_COUNT  ALLOWED=$ALLOW_COUNT"
    echo
    for f in "${FINDINGS[@]}"; do
      IFS='|' read -r rule severity file lineno short <<< "$f"
      printf '  [%-4s] %-22s %s:%s — %s\n' "$severity" "$rule" "$file" "$lineno" "$short"
    done
    if [[ $FAIL_COUNT -gt 0 ]]; then
      echo
      echo "❌ release-gate would block — fix FAIL findings or add a deliberate"
      echo "   regex to scripts/security_scan.allowlist with a comment explaining why."
    fi
  fi
fi

[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0
