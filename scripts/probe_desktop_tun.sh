#!/usr/bin/env bash
set -euo pipefail

START_MS=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)

CONTROLLER="${YUELINK_CONTROLLER:-127.0.0.1:9090}"
SECRET="${YUELINK_SECRET:-}"
MIXED_PORT="${YUELINK_MIXED_PORT:-7890}"
APP_VERSION="${YUELINK_APP_VERSION:-unknown}"
CORE_VERSION="unknown"
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')"
TUN_STACK="${YUELINK_TUN_STACK:-mixed}"
START_CMD="${YUELINK_START_CMD:-}"
STOP_CMD="${YUELINK_STOP_CMD:-}"

if [[ -n "$START_CMD" ]]; then
  bash -lc "$START_CMD" >/dev/null 2>/dev/null || true
  sleep "${YUELINK_START_SETTLE_SECONDS:-3}"
fi

json_bool() {
  if "$@"; then printf true; else printf false; fi
}

curl_controller() {
  if [[ -n "$SECRET" ]]; then
    curl -fsS --max-time 3 -H "Authorization: Bearer $SECRET" \
      "http://$CONTROLLER/version" >/tmp/yuelink-controller-version.json 2>/dev/null
  else
    curl -fsS --max-time 3 "http://$CONTROLLER/version" \
      >/tmp/yuelink-controller-version.json 2>/dev/null
  fi
}

has_admin() {
  [[ "$(id -u 2>/dev/null || echo 1)" == "0" ]]
}

driver_present() {
  case "$PLATFORM" in
    darwin) command -v ifconfig >/dev/null ;;
    linux) [[ -c /dev/net/tun ]] ;;
    *) false ;;
  esac
}

interface_present() {
  case "$PLATFORM" in
    darwin) ifconfig 2>/dev/null | grep -E '^utun[0-9]+:' >/dev/null ;;
    linux) ip addr 2>/dev/null | grep -Ei '^[0-9]+: (tun|yuelink|mihomo)' >/dev/null ;;
    *) false ;;
  esac
}

route_ok() {
  case "$PLATFORM" in
    darwin) netstat -rn 2>/dev/null | grep -q 'utun' ;;
    linux) ip route 2>/dev/null | grep -Ei 'dev (tun|yuelink|mihomo)' >/dev/null ;;
    *) false ;;
  esac
}

dns_ok() {
  if [[ -n "$SECRET" ]]; then
    curl -fsS --max-time 4 -H "Authorization: Bearer $SECRET" \
      "http://$CONTROLLER/dns/query?name=www.gstatic.com&type=A" >/dev/null 2>/dev/null
  else
    curl -fsS --max-time 4 \
      "http://$CONTROLLER/dns/query?name=www.gstatic.com&type=A" >/dev/null 2>/dev/null
  fi
}

https_ok() {
  curl -fsS --noproxy '*' --max-time 6 "$1" >/dev/null 2>/dev/null
}

status_code() {
  curl -k -sS -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 8 "$1" 2>/dev/null || printf timeout
}

cleanup_ok() {
  ! interface_present
}

controller_ok=false
if curl_controller; then
  controller_ok=true
  CORE_VERSION="$(python3 - <<'PY'
import json
try:
  print(json.load(open('/tmp/yuelink-controller-version.json')).get('version','unknown'))
except Exception:
  print('unknown')
PY
)"
fi

transport_ok=$(json_bool https_ok "https://www.gstatic.com/generate_204")
google_ok="$transport_ok"
github_ok=$(json_bool https_ok "https://github.com/")
claude_status="$(status_code https://claude.ai/)"
chatgpt_status="$(status_code https://chatgpt.com/)"

END_MS=$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)
ELAPSED=$((END_MS - START_MS))

error_class=ok
if ! driver_present; then error_class=missing_driver
elif ! has_admin; then error_class=missing_permission
elif [[ "$controller_ok" != true ]]; then error_class=controller_failed
elif ! interface_present; then error_class=tun_interface_missing
elif ! route_ok; then error_class=route_not_applied
elif ! dns_ok; then error_class=dns_hijack_failed
elif [[ "$transport_ok" != true && "$github_ok" != true ]]; then error_class=node_timeout
fi

has_admin_json=$(json_bool has_admin)
driver_present_json=$(json_bool driver_present)
interface_present_json=$(json_bool interface_present)
route_ok_json=$(json_bool route_ok)
dns_ok_json=$(json_bool dns_ok)
if [[ -n "$STOP_CMD" ]]; then
  bash -lc "$STOP_CMD" >/dev/null 2>/dev/null || true
  sleep "${YUELINK_STOP_SETTLE_SECONDS:-3}"
fi
cleanup_ok_json=$(json_bool cleanup_ok)

python3 - <<PY
import json
print(json.dumps({
  "platform": "$PLATFORM",
  "app_version": "$APP_VERSION",
  "core_version": "$CORE_VERSION",
  "tun_stack": "$TUN_STACK",
  "has_admin": json.loads("$has_admin_json"),
  "driver_present": json.loads("$driver_present_json"),
  "interface_present": json.loads("$interface_present_json"),
  "controller_ok": json.loads("$controller_ok"),
  "route_ok": json.loads("$route_ok_json"),
  "dns_ok": json.loads("$dns_ok_json"),
  "transport_ok": json.loads("$transport_ok"),
  "google_ok": json.loads("$google_ok"),
  "github_ok": json.loads("$github_ok"),
  "claude_status": "$claude_status",
  "chatgpt_status": "$chatgpt_status",
  "cleanup_ok": json.loads("$cleanup_ok_json"),
  "error_class": "$error_class",
  "elapsed_ms": $ELAPSED
}, ensure_ascii=False, indent=2))
PY
