import http from 'k6/http';
import { check } from 'k6';
import { Rate } from 'k6/metrics';

const allowedRate = new Rate('limitcore_allowed_ratio');
const deniedRate = new Rate('limitcore_denied_ratio');
const vus = Number(__ENV.LIMITCORE_BENCH_VUS || 10);
const duration = __ENV.LIMITCORE_BENCH_DURATION || '30s';
const distinctKeys = Number(__ENV.LIMITCORE_BENCH_KEYS || 100);
const latencyBudgetMs = Number(__ENV.LIMITCORE_BENCH_P95_MS || 500);

if (!Number.isInteger(vus) || vus < 1 ||
    !Number.isInteger(distinctKeys) || distinctKeys < 1 ||
    !Number.isFinite(latencyBudgetMs) || latencyBudgetMs <= 0) {
  throw new Error('Invalid benchmark configuration');
}

export const options = {
  scenarios: { steady: { executor: 'constant-vus', vus, duration } },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<' + latencyBudgetMs],
  },
};

export default function () {
  const url = __ENV.LIMITCORE_URL || 'http://localhost:8080/v1/limits/check';
  const key = __ENV.LIMITCORE_API_KEY;
  if (!key) throw new Error('Set LIMITCORE_API_KEY');
  const response = http.post(url, JSON.stringify({ key: 'benchmark-' + (__VU % distinctKeys) }), {
    headers: { 'Content-Type': 'application/json', 'X-API-Key': key },
    timeout: '10s',
  });
  const valid = check(response, {
    'HTTP 200': r => r.status === 200,
    'boolean decision': r => r.status === 200 && typeof r.json('allowed') === 'boolean',
  });
  if (valid) {
    const allowed = response.json('allowed');
    allowedRate.add(allowed);
    deniedRate.add(!allowed);
  }
}
