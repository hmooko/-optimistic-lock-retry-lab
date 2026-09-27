#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:?usage: bash scripts/record-docker-environment.sh <app|db|load>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/results/environment"
OUTPUT_FILE="${OUTPUT_DIR}/${ROLE}.txt"

mkdir -p "${OUTPUT_DIR}"

{
  echo "role=${ROLE}"
  echo "recorded_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host=$(hostname)"
  echo "kernel=$(uname -srmo)"
  echo "docker_server_version=$(docker version --format '{{.Server.Version}}')"
  echo "docker_compose_version=$(docker compose version --short)"
  echo
  echo "[images]"
  docker image ls --digests --format '{{.Repository}}:{{.Tag}} digest={{.Digest}} id={{.ID}}'
  echo
  echo "[containers]"
  docker ps --no-trunc --format '{{.Names}} image={{.Image}} id={{.ID}} status={{.Status}}'
} > "${OUTPUT_FILE}"

echo "Environment snapshot written to ${OUTPUT_FILE}"
