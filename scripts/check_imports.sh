#!/usr/bin/env bash
# Architecture import guard — prevents layering violations.
#
# Rules:
#   1. modules/ must NOT import from datasources/ directly
#      (use repository or store_repository re-exports instead)
#   2. domain/ must NOT import from modules/ or infrastructure/
#   3. core/   must NOT import or export modules/
#      (known exception: lib/core/lifecycle/app_resume_controller.dart —
#      coordinates VPN revocation, transport flips, post-resume health
#      recovery, system-proxy tamper detection. Inherently spans modules
#      because resume affects auth / nodes / connections / dashboard
#      providers atomically. Belongs in a future lib/app/ orchestration
#      layer; pragmatically exempted here to avoid Phase 2's controller-
#      split landing as a 10-file path-rename PR.)
#   4. shared/ must NOT import or export modules/
#      (known exceptions — same "app-orchestration belongs in lib/app/"
#      caveat as above. Each controller below is the single instance of
#      its concern in the entire app, owned by `_YueLinkAppState`:
#        - lib/shared/desktop/app_tray_controller.dart  (system tray)
#        - lib/shared/desktop/hotkey_controller.dart    (global hotkey)
#        - lib/shared/main_shell.dart                   (tab navigation)
#        - lib/shared/mobile/android_tile_controller.dart (QS tile)
#      Tray was the original exception; the others were extracted from
#      main.dart in Phase 2 and inherit the same rationale. Slated for
#      relocation to lib/app/ in v1.1+.)
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

# Rule 3: core/ must not import or export modules/
# Anchored at line start so commentary mentioning "modules/" is ignored;
# the `["'/]modules/` character class prevents false positives on sibling
# paths whose name happens to end in `_modules/` (e.g. surge_modules/).
# AppResumeController is exempted — see header comment for rationale.
VIOLATIONS=$(grep -rnE "^[[:space:]]*(import|export) .*[\"'/]modules/" lib/core 2>/dev/null \
  | grep -v "lib/core/lifecycle/app_resume_controller.dart:" \
  || true)
if [ -n "$VIOLATIONS" ]; then
  echo ""
  echo "❌ Rule 3 VIOLATED: core/ imports or re-exports modules/"
  echo "   Fix: core/ must stay independent of feature modules"
  echo "$VIOLATIONS" | while read -r line; do echo "   $line"; done
  ERRORS=$((ERRORS + 1))
fi

# Rule 4: shared/ must not import or export modules/
# Known exceptions — see header comment for rationale (Phase 2 controller
# split; awaiting relocation to lib/app/ in v1.1+).
VIOLATIONS=$(grep -rnE "^[[:space:]]*(import|export) .*[\"'/]modules/" lib/shared 2>/dev/null \
  | grep -v "lib/shared/desktop/app_tray_controller.dart:" \
  | grep -v "lib/shared/desktop/hotkey_controller.dart:" \
  | grep -v "lib/shared/main_shell.dart:" \
  | grep -v "lib/shared/mobile/android_tile_controller.dart:" \
  || true)
if [ -n "$VIOLATIONS" ]; then
  echo ""
  echo "❌ Rule 4 VIOLATED: shared/ imports or re-exports modules/"
  echo "   Fix: shared/ must not depend on feature modules (except the"
  echo "        documented tray exception)"
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
