#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
mkdir -p results

bash scripts/run-k6-docker.sh run   -e BASE_URL="${BASE_URL}"   -e RATE="${RATE:-100}"   -e WARMUP="${WARMUP:-5s}"   -e DURATION="${DURATION:-10s}"   -e REPETITION=1   -e OUTPUT=results/smoke.json   -e STRATEGY="${STRATEGY:-OPT_IMMEDIATE}"   -e HOT_SET="${HOT_SET:-5}"   k6/benchmark.js

echo "Smoke-test result written to results/smoke.json"
