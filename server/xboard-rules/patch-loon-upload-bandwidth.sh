#!/usr/bin/env bash
# Patch XBoard Loon HY2 subscription output to include upload-bandwidth.
# Re-run after container image upgrades if upstream has not fixed it.
set -euo pipefail
cd /home/xboard/yue-to
docker cp /home/xboard/yue-to/patch-loon-upload-bandwidth.php yue-to-web-1:/tmp/patch-loon-upload-bandwidth.php >/dev/null
docker exec yue-to-web-1 php /tmp/patch-loon-upload-bandwidth.php
docker exec yue-to-web-1 php -l /www/app/Protocols/Loon.php
