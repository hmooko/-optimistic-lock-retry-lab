#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8080}"
RATE="${RATE:-800}"
HOT_SET="${HOT_SET:-1}"
WARMUP="${WARMUP:-20s}"
WARMUP_DRAIN="${WARMUP_DRAIN:-10s}"
DURATION="${DURATION:-60s}"
REPETITIONS="${REPETITIONS:-5}"
PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS:-1500}"
MAX_VUS="${MAX_VUS:-3000}"
TX_WORK_MS_VALUES="${TX_WORK_MS_VALUES:-2 5 10 20}"

STRATEGIES=(
  PESSIMISTIC
  OPT_IMMEDIATE
  OPT_FIXED
  OPT_FIXED_JITTER
  OPT_EXPONENTIAL
  OPT_EXPONENTIAL_JITTER
)

read -r -a TX_WORK_VALUES <<< "${TX_WORK_MS_VALUES}"

mkdir -p results/tx-work

for repetition in $(seq 1 "${REPETITIONS}"); do
  combinations=()

  for tx_work_ms in "${TX_WORK_VALUES[@]}"; do
    for strategy in "${STRATEGIES[@]}"; do
      combinations+=("${strategy}:${tx_work_ms}")
    done
  done

  mapfile -t shuffled < <(printf '%s\n' "${combinations[@]}" | shuf)

  for combination in "${shuffled[@]}"; do
    strategy="${combination%%:*}"
    tx_work_ms="${combination##*:}"
    output="results/tx-work/${strategy}_work${tx_work_ms}ms_hot${HOT_SET}_rps${RATE}_run${repetition}.json"

    echo "==> strategy=${strategy} tx_work_ms=${tx_work_ms} hot_set=${HOT_SET} rate=${RATE} run=${repetition}"

    bash scripts/run-k6-docker.sh run \
      -e BASE_URL="${BASE_URL}" \
      -e RATE="${RATE}" \
      -e WARMUP="${WARMUP}" \
      -e WARMUP_DRAIN="${WARMUP_DRAIN}" \
      -e DURATION="${DURATION}" \
      -e REPETITION="${repetition}" \
      -e OUTPUT="${output}" \
      -e STRATEGY="${strategy}" \
      -e HOT_SET="${HOT_SET}" \
      -e TX_WORK_MS="${tx_work_ms}" \
      -e PRE_ALLOCATED_VUS="${PRE_ALLOCATED_VUS}" \
      -e MAX_VUS="${MAX_VUS}" \
      k6/benchmark.js

    sleep 10
  done
done

echo
echo "Completed transaction-work matrix."
echo "Aggregate with:"
echo "  bash scripts/aggregate-results-docker.sh --input-glob 'results/tx-work/*_run*.json' --runs-output results/tx-work/runs.csv --summary-output results/tx-work/summary.csv"
