#!/usr/bin/env bash
# Wintun bundle verifier — Linux/macOS side of the gate.
#
# CI uses the .ps1 sibling on Windows runners; this version is for local
# inspection on dev hosts (the most common YueLink dev setup is macOS,
# where reviewers occasionally fetch a Windows artifact to audit).
#
# Usage:
#   bash scripts/check_windows_wintun_bundle.sh --verify <bundle-dir>
#   bash scripts/check_windows_wintun_bundle.sh --verify-third-party
#
# --verify <dir>            Verify a built/extracted Windows bundle —
#                           expects wintun.dll next to yuelink.exe.
# --verify-third-party      Verify windows/third_party/wintun/{amd64,arm64}
#                           against pinned wintun.sha256.
# --json                    Emit JSON output instead of text.
# --arch <amd64|arm64|both> Restrict to one arch when --verify-third-party.
#
# Exit codes:
#   0 = bundle ok
#   1 = missing dll
#   2 = arch mismatch
#   3 = hash mismatch
#   4 = usage error

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HASH_FILE="$REPO_ROOT/windows/third_party/wintun/wintun.sha256"
THIRD_PARTY_DIR="$REPO_ROOT/windows/third_party/wintun"

MODE=""
BUNDLE_DIR=""
JSON=0
ARCH_FILTER="both"

usage() {
  sed -n '3,16p' "$0"
  exit 4
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --verify)
      MODE="bundle"
      BUNDLE_DIR="${2:-}"
      [[ -z "$BUNDLE_DIR" ]] && usage
      shift 2
      ;;
    --verify-third-party)
      MODE="third-party"
      shift
      ;;
    --arch)
      ARCH_FILTER="${2:-both}"
      shift 2
      ;;
    --json)
      JSON=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      ;;
  esac
done

[[ -z "$MODE" ]] && usage

# Cross-platform sha256: macOS uses `shasum -a 256`, Linux uses `sha256sum`.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "no sha256 tool found (install coreutils or use macOS shasum)" >&2
    exit 4
  fi
}

emit_text() {
  local status="$1" arch="$2" path="$3" detail="$4"
  printf '  [%s] %-5s %s%s\n' "$status" "$arch" "$path" \
    "${detail:+ — $detail}"
}

# Build a JSON entry. Caller passes status/arch/path/detail; we keep the
# JSON shape stable so release-gate.yml can parse it.
JSON_RESULTS=()
emit_json() {
  local status="$1" arch="$2" path="$3" detail="$4"
  JSON_RESULTS+=(
    "$(printf '{"status":"%s","arch":"%s","path":"%s","detail":"%s"}' \
        "$status" "$arch" "$path" "$detail")"
  )
}

emit() {
  if [[ "$JSON" -eq 1 ]]; then
    emit_json "$@"
  else
    emit_text "$@"
  fi
}

ERRORS=0

# Pull pinned hashes (skip comments/blanks). Format: "<hash>  <relpath>".
expected_hash() {
  local key="$1"
  awk -v k="$key" '
    /^#/ {next}
    NF == 2 && $2 == k {print $1; exit}
  ' "$HASH_FILE"
}

# ── Mode: verify a built bundle (post flutter-build) ────────────────────
if [[ "$MODE" == "bundle" ]]; then
  if [[ ! -d "$BUNDLE_DIR" ]]; then
    emit "fail" "-" "$BUNDLE_DIR" "directory not found"
    ERRORS=1
  else
    # Find wintun.dll anywhere in the bundle. flutter build windows puts
    # it next to yuelink.exe via the install rule; safer to recurse so
    # custom packaging layouts (Inno-installed, manual zip) still pass.
    found=$(find "$BUNDLE_DIR" -iname 'wintun.dll' -type f 2>/dev/null | head -5 || true)
    if [[ -z "$found" ]]; then
      emit "fail" "-" "$BUNDLE_DIR/wintun.dll" "missing — would assert false running on launch"
      ERRORS=1
    else
      while IFS= read -r dll; do
        [[ -z "$dll" ]] && continue
        h="$(sha256_of "$dll")"
        # Match against either pinned hash; exact arch match is the
        # ideal but on builds where only one arch ships, check both.
        h_amd="$(expected_hash 'amd64/wintun.dll')"
        h_arm="$(expected_hash 'arm64/wintun.dll')"
        if [[ "$h" == "$h_amd" ]]; then
          emit "ok" "amd64" "$dll" ""
        elif [[ "$h" == "$h_arm" ]]; then
          emit "ok" "arm64" "$dll" ""
        else
          emit "fail" "?" "$dll" "hash $h matches neither pinned amd64/arm64 — possible substitution"
          ERRORS=1
        fi
      done <<< "$found"
    fi
  fi
fi

# ── Mode: verify the source-of-truth third-party tree ──────────────────
if [[ "$MODE" == "third-party" ]]; then
  if [[ ! -f "$HASH_FILE" ]]; then
    emit "fail" "-" "$HASH_FILE" "pinned hash file missing"
    ERRORS=1
  else
    archs=()
    case "$ARCH_FILTER" in
      both)  archs=(amd64 arm64) ;;
      amd64) archs=(amd64) ;;
      arm64) archs=(arm64) ;;
      *)     echo "bad --arch: $ARCH_FILTER (use amd64|arm64|both)" >&2; exit 4 ;;
    esac
    for a in "${archs[@]}"; do
      f="$THIRD_PARTY_DIR/$a/wintun.dll"
      if [[ ! -f "$f" ]]; then
        emit "fail" "$a" "$f" "missing — run check_windows_wintun_bundle.ps1 -Download"
        ERRORS=1
        continue
      fi
      h="$(sha256_of "$f")"
      want="$(expected_hash "$a/wintun.dll")"
      if [[ -z "$want" ]]; then
        emit "fail" "$a" "$f" "no pinned hash for $a/wintun.dll in $HASH_FILE"
        ERRORS=1
      elif [[ "$h" == "$want" ]]; then
        emit "ok" "$a" "$f" ""
      else
        emit "fail" "$a" "$f" "sha256 mismatch (got $h, want $want)"
        ERRORS=1
      fi
    done
  fi
fi

# ── Output ──────────────────────────────────────────────────────────────
if [[ "$JSON" -eq 1 ]]; then
  printf '{"mode":"%s","ok":%s,"errors":%d,"results":[' \
    "$MODE" "$([ $ERRORS -eq 0 ] && echo true || echo false)" "$ERRORS"
  for i in "${!JSON_RESULTS[@]}"; do
    [[ $i -gt 0 ]] && printf ','
    printf '%s' "${JSON_RESULTS[$i]}"
  done
  printf ']}\n'
else
  if [[ $ERRORS -eq 0 ]]; then
    echo "✅ Wintun bundle ok"
  else
    echo "❌ Wintun bundle failed ($ERRORS issue(s))"
  fi
fi

if [[ $ERRORS -gt 0 ]]; then
  # Distinguish exit codes per docstring: 1 missing / 3 hash mismatch.
  # Cheaper to scan results than thread state through the loops above.
  if [[ "$JSON" -eq 1 ]]; then
    if printf '%s' "${JSON_RESULTS[@]:-}" | grep -q '"hash'; then
      exit 3
    fi
  fi
  exit 1
fi
exit 0
