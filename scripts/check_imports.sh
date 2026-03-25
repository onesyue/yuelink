#!/usr/bin/env bash
# Architecture import guard — prevents layering violations.
#
# Rules:
#   1. modules/ must NOT import from datasources/ directly
#      (use repository or store_repository re-exports instead)
#   2. domain/ must NOT import from modules/ or infrastructure/
#
# Run: bash scripts/check_imports.sh
# Exit: 0 = clean, 1 = violations found

set -euo pipefail

ERRORS=0

echo "🔍 Checking architecture import rules..."

# Rule 1: modules/ must not import datasources/ directly
# Exceptions:
#   - yue_auth (defines xboardApiProvider — the canonical gateway)
#   - carrier (yueops_api is carrier-module-specific, no shared repository yet)
VIOLATIONS=$(grep -rn "import.*datasources/" lib/modules/ \
  | grep -v "yue_auth/" \
  | grep -v "carrier/" \
  2>/dev/null || true)
if [ -n "$VIOLATIONS" ]; then
  echo ""
  echo "❌ Rule 1 VIOLATED: modules/ imports datasources/ directly"
  echo "   Fix: import from repository layer instead"
  echo "$VIOLATIONS" | while read -r line; do echo "   $line"; done
  ERRORS=$((ERRORS + 1))
fi

# Rule 2: domain/ must not import modules/ or infrastructure/
VIOLATIONS=$(grep -rn "import.*modules/\|import.*infrastructure/" lib/domain/ 2>/dev/null || true)
if [ -n "$VIOLATIONS" ]; then
  echo ""
  echo "❌ Rule 2 VIOLATED: domain/ imports modules/ or infrastructure/"
  echo "   Fix: domain layer must only depend on dart:* and other domain files"
  echo "$VIOLATIONS" | while read -r line; do echo "   $line"; done
  ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
  echo "✅ All import rules passed"
  exit 0
else
  echo ""
  echo "Found $ERRORS rule violation(s)"
  exit 1
fi
