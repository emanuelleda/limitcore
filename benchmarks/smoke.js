import http from 'k6/http';
import { check } from 'k6';

export const options = {
  scenarios: { smoke: { executor: 'constant-vus', vus: 2, duration: '10s' } },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
  },
};

export default function () {
  const key = __ENV.LIMITCORE_API_KEY;
  if (!key) throw new Error('LIMITCORE_API_KEY is required');
  const endpoint = __ENV.LIMITCORE_URL || 'http://localhost:8080/v1/limits/check';
  const response = http.post(endpoint, JSON.stringify({ key: 'smoke-' + __VU }), {
    headers: { 'X-API-Key': key, 'Content-Type': 'application/json' },
    timeout: '5s',
  });
  check(response, {
    'HTTP 200': r => r.status === 200,
    'decision boolean': r => r.status === 200 && typeof r.json('allowed') === 'boolean',
  });
}
