#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-status}"
APP_SSH="${APP_SSH:-retry-app}"
DB_SSH="${DB_SSH:-retry-db}"
LOAD_SSH="${LOAD_SSH:-retry-load}"
CONTROL_DIR="/tmp/retry-lab-monitoring-${USER}"

mkdir -p "$CONTROL_DIR"

start_tunnel() {
  local name="$1"
  local host="$2"
  shift 2
  local socket="$CONTROL_DIR/${name}.sock"

  if ssh -S "$socket" -O check "$host" >/dev/null 2>&1; then
    echo "${name}: already running"
    return
  fi

  rm -f "$socket"
  ssh -M -S "$socket" -fnNT     -o ExitOnForwardFailure=yes     -o ServerAliveInterval=30     -o ServerAliveCountMax=3     "$@"     "$host"

  echo "${name}: started"
}

stop_tunnel() {
  local name="$1"
  local host="$2"
  local socket="$CONTROL_DIR/${name}.sock"

  if ssh -S "$socket" -O check "$host" >/dev/null 2>&1; then
    ssh -S "$socket" -O exit "$host" >/dev/null
    echo "${name}: stopped"
  else
    rm -f "$socket"
    echo "${name}: not running"
  fi
}

status_tunnel() {
  local name="$1"
  local host="$2"
  local socket="$CONTROL_DIR/${name}.sock"

  if ssh -S "$socket" -O check "$host" >/dev/null 2>&1; then
    echo "${name}: running"
  else
    echo "${name}: stopped"
  fi
}

case "$ACTION" in
  start)
    start_tunnel app "$APP_SSH"       -L 18080:127.0.0.1:8080       -L 19100:127.0.0.1:9100
    start_tunnel db "$DB_SSH"       -L 19101:127.0.0.1:9100
    start_tunnel load "$LOAD_SSH"       -L 19102:127.0.0.1:9100
    ;;
  stop)
    stop_tunnel app "$APP_SSH"
    stop_tunnel db "$DB_SSH"
    stop_tunnel load "$LOAD_SSH"
    ;;
  status)
    status_tunnel app "$APP_SSH"
    status_tunnel db "$DB_SSH"
    status_tunnel load "$LOAD_SSH"
    ;;
  *)
    echo "Usage: $0 <start|stop|status>" >&2
    exit 2
    ;;
esac
