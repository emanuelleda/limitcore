import http from 'k6/http';
import { check } from 'k6';
export const options = {
  scenarios: { steady: { executor: 'constant-vus', vus: 10, duration: '30s' } },
  thresholds: { http_req_failed: ['rate<0.01'], http_req_duration: ['p(95)<500'] }
};
export default function () {
  const url = __ENV.LIMITCORE_URL || 'http://localhost:8080/v1/limits/check';
  const key = __ENV.LIMITCORE_API_KEY;
  if (!key) throw new Error('Set LIMITCORE_API_KEY');
  const res = http.post(url, JSON.stringify({ key: 'benchmark' }), {
    headers: { 'Content-Type': 'application/json', 'X-API-Key': key }
  });
  check(res, { 'valid decision': r => r.status === 200 && typeof r.json('allowed') === 'boolean' });
}
