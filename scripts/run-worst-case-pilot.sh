#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
RATE="${RATE:-1000}"
HOT_SET="${HOT_SET:-1}"
WARMUP="${WARMUP:-20s}"
WARMUP_DRAIN="${WARMUP_DRAIN:-10s}"
DURATION="${DURATION:-60s}"
PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS:-1500}"
MAX_VUS="${MAX_VUS:-3000}"
PAUSE_SECONDS="${PAUSE_SECONDS:-10}"

STRATEGIES=(
  PESSIMISTIC
  OPT_IMMEDIATE
  OPT_FIXED
  OPT_FIXED_JITTER
  OPT_EXPONENTIAL
  OPT_EXPONENTIAL_JITTER
)

mkdir -p results

failed=0

for strategy in "${STRATEGIES[@]}"; do
  output="results/pilot_${strategy}_hot${HOT_SET}_rate${RATE}.json"

  echo
  echo "==> pilot strategy=${strategy} hot_set=${HOT_SET} rate=${RATE}"

  if bash scripts/run-k6-docker.sh run \
    -e BASE_URL="${BASE_URL}" \
    -e RATE="${RATE}" \
    -e WARMUP="${WARMUP}" \
    -e WARMUP_DRAIN="${WARMUP_DRAIN}" \
    -e DURATION="${DURATION}" \
    -e REPETITION=0 \
    -e OUTPUT="${output}" \
    -e STRATEGY="${strategy}" \
    -e HOT_SET="${HOT_SET}" \
    -e PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS}" \
    -e MAX_VUS="${MAX_VUS}" \
    k6/benchmark.js; then
    echo "PASS: measurement dropped iterations = 0"
  else
    echo "FAIL: measurement dropped-iteration threshold was crossed or k6 failed"
    failed=1
  fi

  if [[ -f "${output}" ]]; then
    cat "${output}"
  else
    echo "Missing output: ${output}" >&2
    failed=1
  fi

  sleep "${PAUSE_SECONDS}"
done

echo
if [[ "${failed}" -eq 0 ]]; then
  echo "All six worst-case pilots passed with zero measurement dropped iterations."
else
  echo "One or more worst-case pilots failed. Do not start the main matrix yet." >&2
fi

exit "${failed}"
