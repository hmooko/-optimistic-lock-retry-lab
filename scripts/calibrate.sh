#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
WARMUP="${WARMUP:-10s}"
DURATION="${DURATION:-30s}"
RATES=(100 200 300 400 500 600)

mkdir -p results/calibration

for rate in "${RATES[@]}"; do
  output="results/calibration/rate_${rate}.json"
  echo "==> calibration rate=${rate}"

  bash scripts/run-k6-docker.sh run     -e BASE_URL="${BASE_URL}"     -e RATE="${rate}"     -e WARMUP="${WARMUP}"     -e DURATION="${DURATION}"     -e REPETITION=1     -e OUTPUT="${output}"     -e STRATEGY=OPT_IMMEDIATE     -e HOT_SET=1000     k6/benchmark.js

  sleep 10
done
