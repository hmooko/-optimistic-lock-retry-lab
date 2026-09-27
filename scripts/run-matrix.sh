#!/usr/bin/env bash
set -euo pipefail

: "${RATE:?Set RATE to the calibrated requests/sec value}"

BASE_URL="${BASE_URL:-http://localhost:8080}"
DURATION="${DURATION:-60s}"
REPETITIONS="${REPETITIONS:-5}"

STRATEGIES=(
  PESSIMISTIC
  OPT_IMMEDIATE
  OPT_FIXED
  OPT_FIXED_JITTER
  OPT_EXPONENTIAL
  OPT_EXPONENTIAL_JITTER
)
HOT_SETS=(100 20 5 1)

mkdir -p results

for repetition in $(seq 1 "${REPETITIONS}"); do
  for hot_set in "${HOT_SETS[@]}"; do
    for strategy in "${STRATEGIES[@]}"; do
      output="results/${strategy}_hot${hot_set}_run${repetition}.json"
      echo "==> strategy=${strategy} hot_set=${hot_set} run=${repetition}"
      k6 run         -e BASE_URL="${BASE_URL}"         -e RATE="${RATE}"         -e DURATION="${DURATION}"         -e STRATEGY="${strategy}"         -e HOT_SET="${hot_set}"         --summary-export "${output}"         k6/benchmark.js
      sleep 10
    done
  done
done
