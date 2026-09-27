import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const STRATEGY = __ENV.STRATEGY || 'OPT_IMMEDIATE';
const HOT_SET = Number(__ENV.HOT_SET || 100);
const RATE = Number(__ENV.RATE || 400);
const DURATION = __ENV.DURATION || '60s';
const PRE_ALLOCATED_VUS = Number(__ENV.PRE_ALLOCATED_VUS || 100);
const MAX_VUS = Number(__ENV.MAX_VUS || 1000);

const successfulPurchases = new Counter('successful_purchases');
const failedPurchases = new Counter('failed_purchases');
const retryAttempts = new Counter('retry_attempts');

export const options = {
  scenarios: {
    purchase: {
      executor: 'constant-arrival-rate',
      rate: RATE,
      timeUnit: '1s',
      duration: DURATION,
      preAllocatedVUs: PRE_ALLOCATED_VUS,
      maxVUs: MAX_VUS,
    },
  },
  thresholds: {
    dropped_iterations: ['count==0'],
  },
};

export function setup() {
  const productCount = Math.max(100, HOT_SET);
  const reset = http.post(
    `${BASE_URL}/api/admin/reset?productCount=${productCount}&stock=1000000`
  );
  if (reset.status !== 200) {
    throw new Error(`reset failed: status=${reset.status}, body=${reset.body}`);
  }
}

export default function () {
  const productId = Math.floor(Math.random() * HOT_SET) + 1;
  const response = http.post(
    `${BASE_URL}/api/purchases/${productId}?strategy=${STRATEGY}`
  );

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
