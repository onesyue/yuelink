#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOST="${YUELINK_PROD_HOST:-23.80.91.14}"
USER="${YUELINK_PROD_USER:-root}"
REMOTE_DIR="${YUELINK_REMOTE_DIR:-/opt/checkin-api}"
TS="$(date +%Y%m%d-%H%M%S)"
REMOTE_TMP="/tmp/yuelink-telemetry-dashboard-${TS}"

: "${TELEMETRY_DASHBOARD_USER:?set TELEMETRY_DASHBOARD_USER}"
: "${TELEMETRY_DASHBOARD_PASSWORD:?set TELEMETRY_DASHBOARD_PASSWORD}"

SSH_BASE=(ssh -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=15)
SCP_BASE=(scp -o StrictHostKeyChecking=accept-new)
if [[ -n "${YUELINK_SSH_PASSWORD:-}" ]]; then
  export SSHPASS="${YUELINK_SSH_PASSWORD}"
  SSH_BASE=(sshpass -e "${SSH_BASE[@]}")
  SCP_BASE=(sshpass -e "${SCP_BASE[@]}")
fi

REMOTE="${USER}@${HOST}"

ssh_cmd() {
  "${SSH_BASE[@]}" "${REMOTE}" "$@"
}

scp_to_remote() {
  "${SCP_BASE[@]}" "$1" "${REMOTE}:$2"
}

echo "[deploy] staging files on ${REMOTE}:${REMOTE_TMP}"
ssh_cmd "mkdir -p '${REMOTE_TMP}'"
scp_to_remote "${ROOT_DIR}/server/telemetry/telemetry.py" "${REMOTE_TMP}/telemetry.py"
scp_to_remote "${ROOT_DIR}/server/telemetry/dashboard.html" "${REMOTE_TMP}/dashboard.html"

echo "[deploy] installing dashboard router and restarting checkin-api"
printf -v REMOTE_AUTH_USER "%q" "${TELEMETRY_DASHBOARD_USER}"
printf -v REMOTE_AUTH_PASSWORD "%q" "${TELEMETRY_DASHBOARD_PASSWORD}"
printf -v REMOTE_DIR_Q "%q" "${REMOTE_DIR}"
printf -v REMOTE_TMP_Q "%q" "${REMOTE_TMP}"
printf -v TS_Q "%q" "${TS}"
ssh_cmd \
  "TELEMETRY_DASHBOARD_USER=${REMOTE_AUTH_USER} TELEMETRY_DASHBOARD_PASSWORD=${REMOTE_AUTH_PASSWORD} REMOTE_DIR=${REMOTE_DIR_Q} REMOTE_TMP=${REMOTE_TMP_Q} TS=${TS_Q} bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail

rollback() {
  echo "[deploy] rollback triggered"
  if [[ -f "${REMOTE_DIR}/main.py.bak-${TS}" ]]; then
    cp "${REMOTE_DIR}/main.py.bak-${TS}" "${REMOTE_DIR}/main.py"
  fi
  if [[ -f "${REMOTE_DIR}/telemetry.py.bak-${TS}" ]]; then
    cp "${REMOTE_DIR}/telemetry.py.bak-${TS}" "${REMOTE_DIR}/telemetry.py"
  fi
  systemctl restart checkin-api || true
}

trap 'rollback' ERR

cd "${REMOTE_DIR}"
cp main.py "main.py.bak-${TS}"
if [[ -f telemetry.py ]]; then
  cp telemetry.py "telemetry.py.bak-${TS}"
fi
if [[ -f dashboard.html ]]; then
  cp dashboard.html "dashboard.html.bak-${TS}"
fi

install -m 0644 "${REMOTE_TMP}/telemetry.py" "${REMOTE_DIR}/telemetry.py"
install -m 0644 "${REMOTE_TMP}/dashboard.html" "${REMOTE_DIR}/dashboard.html"

mkdir -p /etc/systemd/system/checkin-api.service.d
cat > /etc/systemd/system/checkin-api.service.d/zz-yuelink-telemetry-dashboard.conf <<EOF
[Service]
Environment=TELEMETRY_DASHBOARD_USER=${TELEMETRY_DASHBOARD_USER}
Environment=TELEMETRY_DASHBOARD_PASSWORD=${TELEMETRY_DASHBOARD_PASSWORD}
EOF

python3 - <<'PY'
from pathlib import Path

path = Path("/opt/checkin-api/main.py")
text = path.read_text()
import_line = "from telemetry import router_dashboard as telemetry_dashboard_router\n"
include_line = "app.include_router(telemetry_dashboard_router)\n"

if import_line not in text:
    lines = text.splitlines(keepends=True)
    insert_at = 0
    if lines and lines[0].startswith("#!"):
        insert_at = 1
    while insert_at < len(lines) and lines[insert_at].startswith("from __future__"):
        insert_at += 1
    lines.insert(insert_at, import_line)
    text = "".join(lines)

if include_line not in text:
    marker = "app = FastAPI"
    start = text.find(marker)
    if start == -1:
        raise SystemExit("could not find FastAPI app declaration")
    open_paren = text.find("(", start)
    if open_paren == -1:
        raise SystemExit("could not find FastAPI opening parenthesis")
    depth = 0
    end = None
    for i in range(open_paren, len(text)):
        ch = text[i]
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                newline = text.find("\n", i)
                end = len(text) if newline == -1 else newline + 1
                break
    if end is None:
        raise SystemExit("could not find FastAPI declaration end")
    text = text[:end] + include_line + text[end:]

path.write_text(text)
PY

systemctl daemon-reload
systemctl restart checkin-api
sleep 5

curl -fsS --max-time 8 http://127.0.0.1:8011/api/client/home >/dev/null
curl -fsS --max-time 8 http://127.0.0.1:8011/api/client/telemetry/flags >/dev/null
curl -fsS --max-time 8 -u "${TELEMETRY_DASHBOARD_USER}:${TELEMETRY_DASHBOARD_PASSWORD}" \
  "http://127.0.0.1:8011/api/client/telemetry/stats/versions?days=1" >/dev/null

trap - ERR
rm -rf "${REMOTE_TMP}"
echo "[deploy] ok"
REMOTE_SCRIPT

echo "[deploy] done"
