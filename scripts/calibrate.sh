#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION="${DURATION:-30s}"
RATES=(100 200 300 400 500 600)

mkdir -p results/calibration

for rate in "${RATES[@]}"; do
  echo "==> calibration rate=${rate}"
  k6 run     -e BASE_URL="${BASE_URL}"     -e RATE="${rate}"     -e DURATION="${DURATION}"     -e STRATEGY=OPT_IMMEDIATE     -e HOT_SET=1000     --summary-export "results/calibration/rate_${rate}.json"     k6/benchmark.js
  sleep 10
done
