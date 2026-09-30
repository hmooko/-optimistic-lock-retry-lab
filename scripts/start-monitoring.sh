#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash "$ROOT_DIR/scripts/monitoring-tunnels.sh" start
docker compose -f "$ROOT_DIR/monitoring/compose.yml" up -d

echo
echo "Grafana:    http://localhost:3000"
echo "Prometheus: http://localhost:9090/targets"
echo "Login:      admin / retry-lab-grafana"
