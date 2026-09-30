#!/usr/bin/env bash
set -euo pipefail

APP_SSH="${APP_SSH:-retry-app}"
DB_SSH="${DB_SSH:-retry-db}"
LOAD_SSH="${LOAD_SSH:-retry-load}"
NODE_EXPORTER_IMAGE="${NODE_EXPORTER_IMAGE:-quay.io/prometheus/node-exporter:v1.12.1}"

install_exporter() {
  local role="$1"
  local host="$2"

  echo "==> ${role}: ${host}"
  ssh "$host" bash -s -- "$NODE_EXPORTER_IMAGE" <<'REMOTE'
set -euo pipefail
image="$1"

docker pull "$image"
docker rm -f node-exporter >/dev/null 2>&1 || true

docker run -d   --name node-exporter   --restart unless-stopped   --network host   --pid host   -v /:/host:ro,rslave   "$image"   --path.rootfs=/host   --web.listen-address=127.0.0.1:9100

docker ps --filter name=node-exporter   --format 'node-exporter: {{.Status}}'
REMOTE
}

install_exporter app "$APP_SSH"
install_exporter db "$DB_SSH"
install_exporter load "$LOAD_SSH"

echo "Node Exporter is running on all three experiment servers."
