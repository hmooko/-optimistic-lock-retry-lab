import http from 'k6/http';
import exec from 'k6/execution';
import { check } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const STRATEGY = __ENV.STRATEGY || 'OPT_IMMEDIATE';
const HOT_SET = Number(__ENV.HOT_SET || 100);
const RATE = Number(__ENV.RATE || 400);
const WARMUP = __ENV.WARMUP || '20s';
const DURATION = __ENV.DURATION || '60s';
const REPETITION = Number(__ENV.REPETITION || 1);
const OUTPUT = __ENV.OUTPUT || 'summary.json';
const PRE_ALLOCATED_VUS = Number(__ENV.PRE_ALLOCATED_VUS || 500);
const MAX_VUS = Number(__ENV.MAX_VUS || 1000);

const successfulPurchases = new Counter('successful_purchases');
const failedPurchases = new Counter('failed_purchases');
const retryAttempts = new Counter('retry_attempts');
const purchaseLatency = new Trend('purchase_latency', true);

export const options = {
  summaryTrendStats: ['avg', 'min', 'med', 'max', 'p(95)', 'p(99)'],
  scenarios: {
    warmup: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: WARMUP,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
      exec: 'purchase',
    },
    measure: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      startTime: WARMUP,
      duration: DURATION,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
      exec: 'purchase',
    },
  },
  thresholds: {
    dropped_iterations: ['count==0'],
  },
};

export function setup() {
  const productCount = Math.max(100, HOT_SET);
  const reset = http.post(
    `${BASE_URL}/api/admin/reset?productCount=${productCount}&stock=1000000`,
    null,
    { tags: { phase: 'setup' } }
  );

  if (reset.status !== 200) {
    throw new Error(`reset failed: status=${reset.status}, body=${reset.body}`);
  }
}

export function purchase() {
  const productId = Math.floor(Math.random() * HOT_SET) + 1;
  const response = http.post(
    `${BASE_URL}/api/purchases/${productId}?strategy=${STRATEGY}`,
    null,
    { tags: { phase: exec.scenario.name } }
  );

  if (exec.scenario.name !== 'measure') {
    return;
  }

  purchaseLatency.add(response.timings.duration);

  let body = null;
  try {
    body = response.json();
  } catch (_) {
    // Count malformed responses as failures below.
  }

  if (body && Number.isFinite(body.retries)) {
    retryAttempts.add(body.retries);
  }

  if (response.status === 200) {
    successfulPurchases.add(1);
  } else {
    failedPurchases.add(1);
  }

  check(response, {
    'purchase completed or retry exhausted': (r) => r.status === 200 || r.status === 409,
  });
}

export function handleSummary(data) {
  const successCount = metricValue(data, 'successful_purchases', 'count', 0);
  const failureCount = metricValue(data, 'failed_purchases', 'count', 0);
  const retryCount = metricValue(data, 'retry_attempts', 'count', 0);
  const p99LatencyMs = metricValue(data, 'purchase_latency', 'p(99)', null);
  const durationSeconds = parseDurationSeconds(DURATION);

  const completed = successCount + failureCount;
  const result = {
    metadata: {
      strategy: STRATEGY,
      hotSet: HOT_SET,
      rate: RATE,
      warmup: WARMUP,
      duration: DURATION,
      durationSeconds,
      repetition: REPETITION,
    },
    metrics: {
      successCount,
      failureCount,
      retryCount,
      throughputPerSecond: durationSeconds > 0 ? successCount / durationSeconds : null,
      p99LatencyMs,
      retryAmplification: successCount > 0 ? retryCount / successCount : null,
      failureRate: completed > 0 ? failureCount / completed : null,
      droppedIterations: metricValue(data, 'dropped_iterations', 'count', 0),
    },
  };

  return {
    [OUTPUT]: JSON.stringify(result, null, 2),
  };
}

function metricValue(data, metricName, valueName, fallback) {
  const metric = data.metrics[metricName];
  if (!metric || !metric.values || metric.values[valueName] === undefined) {
    return fallback;
  }
  return metric.values[valueName];
}

function parseDurationSeconds(value) {
  const match = /^(\d+(?:\.\d+)?)(ms|s|m|h)$/.exec(value);
  if (!match) {
    throw new Error(`unsupported duration format: ${value}`);
  }

  const amount = Number(match[1]);
  const unit = match[2];

  switch (unit) {
    case 'ms':
      return amount / 1000;
    case 's':
      return amount;
    case 'm':
      return amount * 60;
    case 'h':
      return amount * 3600;
    default:
      throw new Error(`unsupported duration unit: ${unit}`);
  }
}
