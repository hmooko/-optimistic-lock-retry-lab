#!/usr/bin/env bash
set -euo pipefail

APP_SSH="${APP_SSH:-retry-app}"
DB_SSH="${DB_SSH:-retry-db}"
LOAD_SSH="${LOAD_SSH:-retry-load}"
REMOTE_REPO_PATH="${REMOTE_REPO_PATH:-retry-lab}"
NODE_EXPORTER_IMAGE="${NODE_EXPORTER_IMAGE:-quay.io/prometheus/node-exporter:v1.12.1}"

prepare_server() {
  local role="$1"
  local host="$2"

  echo "==> ${role}: ${host}"
  ssh "$host" bash -s -- "$NODE_EXPORTER_IMAGE" "$REMOTE_REPO_PATH" <<'REMOTE'
set -euo pipefail

image="$1"
repo_path="$2"

case "$repo_path" in
  /*) repo_dir="$repo_path" ;;
  *)  repo_dir="$HOME/$repo_path" ;;
esac

cd "$repo_dir"

branch="$(git branch --show-current)"
if [ "$branch" != "main" ]; then
  echo "Expected main branch in $repo_dir, found: $branch" >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "Tracked local changes found in $repo_dir; refusing to pull." >&2
  exit 1
fi

git pull --ff-only origin main
echo "git revision: $(git rev-parse --short HEAD)"

docker pull "$image"
docker rm -f node-exporter >/dev/null 2>&1 || true

docker run -d \
  --name node-exporter \
  --restart unless-stopped \
  --network host \
  --pid host \
  -v /:/host:ro,rslave \
  "$image" \
  --path.rootfs=/host \
  --web.listen-address=127.0.0.1:9100

docker ps \
  --filter name=node-exporter \
  --format 'node-exporter: {{.Status}}'
REMOTE
}

prepare_server app "$APP_SSH"
prepare_server db "$DB_SSH"
prepare_server load "$LOAD_SSH"

echo "All three servers are on the latest main revision and Node Exporter is running."
