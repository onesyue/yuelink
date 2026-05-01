#!/usr/bin/env bash
# Telemetry endpoint reachability probe.
#
# Catches the regression we hit on 2026-05-01: telemetry router silently
# unmounted from /opt/checkin-api/main.py (or nginx location lost), so
# /api/client/telemetry/* returned 404 / "ok" fallthrough for days while
# we believed the dashboard at memory[project_telemetry_dashboard.md] was
# live. SRE was blind during the v1.1.x stability investigation.
#
# Probes WITHOUT BasicAuth on purpose: a healthy mounted router returns
# 401 (auth challenge). 404 / 200-with-"ok" / 5xx all mean the route
# isn't there. This avoids putting credentials in CI logs.
#
# Run: bash scripts/probe_telemetry.sh
# Override host: TELEMETRY_BASE=https://staging.example.com bash scripts/probe_telemetry.sh
# Exit: 0 = healthy, 1 = unhealthy (nonzero so a scheduled workflow fails)

set -euo pipefail

BASE="${TELEMETRY_BASE:-https://yue.yuebao.website}"
PREFIX="/api/client/telemetry"

# Endpoints to probe. Each protected by BasicAuth → expect HTTP 401.
ENDPOINTS=(
  "$PREFIX/dashboard"
  "$PREFIX/stats/summary?days=1"
  "$PREFIX/stats/versions?days=1"
)

ERRORS=0
echo "🔍 Probing telemetry router at $BASE …"

for path in "${ENDPOINTS[@]}"; do
  url="$BASE$path"
  # -m 10s connect+read budget. Capture HTTP code + body for diagnosis.
  body_file="$(mktemp)"
  http_code="$(curl -sS -m 10 -o "$body_file" -w '%{http_code}' "$url" || echo '000')"
  body_size="$(wc -c < "$body_file" | tr -d ' ')"
  body_head="$(head -c 80 "$body_file" | tr -d '\n')"
  rm -f "$body_file"

  case "$http_code" in
    401)
      # Router mounted, BasicAuth challenged us. Healthy.
      echo "  ✅ $path → 401 (auth challenge — router mounted)"
      ;;
    200)
      # Nginx fallthrough returns literal "ok" 2-byte body. FastAPI router
      # auth dependency would never let unauth'd traffic reach 200.
      if [ "$body_size" = "2" ] && [ "$body_head" = "ok" ]; then
        echo "  ❌ $path → 200 'ok' (nginx fallthrough — router NOT mounted)"
        ERRORS=$((ERRORS + 1))
      else
        echo "  ⚠️  $path → 200 unexpected body (size=$body_size head='$body_head')"
        ERRORS=$((ERRORS + 1))
      fi
      ;;
    404)
      echo "  ❌ $path → 404 (route missing — check include_router + nginx location)"
      ERRORS=$((ERRORS + 1))
      ;;
    000)
      echo "  ❌ $path → connection failed (DNS / TLS / server down)"
      ERRORS=$((ERRORS + 1))
      ;;
    5*)
      echo "  ❌ $path → $http_code (server error — body: $body_head)"
      ERRORS=$((ERRORS + 1))
      ;;
    *)
      echo "  ⚠️  $path → unexpected $http_code (body: $body_head)"
      ERRORS=$((ERRORS + 1))
      ;;
  esac
done

if [ "$ERRORS" -eq 0 ]; then
  echo "✅ Telemetry router healthy — all ${#ENDPOINTS[@]} endpoints challenged auth"
  exit 0
fi

cat <<EOF

Found $ERRORS unhealthy endpoint(s).

Likely fixes:
  1. SSH 23.80.91.14 — check /opt/checkin-api/main.py contains
     'app.include_router(telemetry.router)' and the import is alive.
  2. systemctl status checkin-api — inspect last failure if it crashed.
  3. nginx -T | grep -A 3 'api/client/telemetry' — confirm location { proxy_pass } is intact.
  4. systemctl restart checkin-api after any fix.
EOF

exit 1
