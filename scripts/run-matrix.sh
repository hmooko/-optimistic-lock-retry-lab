#!/usr/bin/env bash
set -euo pipefail

: "${RATE:?Set RATE to the calibrated requests/sec value}"

BASE_URL="${BASE_URL:-http://localhost:8080}"
WARMUP="${WARMUP:-20s}"
DURATION="${DURATION:-60s}"
REPETITIONS="${REPETITIONS:-5}"
PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS:-1000}"
MAX_VUS="${MAX_VUS:-3000}"

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
  combinations=()
  for hot_set in "${HOT_SETS[@]}"; do
    for strategy in "${STRATEGIES[@]}"; do
      combinations+=("${strategy}:${hot_set}")
    done
  done

  mapfile -t shuffled < <(printf '%s\n' "${combinations[@]}" | shuf)

  for combination in "${shuffled[@]}"; do
    strategy="${combination%%:*}"
    hot_set="${combination##*:}"
    output="results/${strategy}_hot${hot_set}_run${repetition}.json"

    echo "==> strategy=${strategy} hot_set=${hot_set} run=${repetition}"

    bash scripts/run-k6-docker.sh run       -e BASE_URL="${BASE_URL}"       -e RATE="${RATE}"       -e WARMUP="${WARMUP}"       -e DURATION="${DURATION}"       -e REPETITION="${repetition}"       -e OUTPUT="${output}"       -e STRATEGY="${strategy}"       -e HOT_SET="${hot_set}"       -e PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS}"       -e MAX_VUS="${MAX_VUS}"       k6/benchmark.js

    sleep 10
  done
done
