// Read-path load test through the public load balancer (what a user sees).
// Install k6 (https://grafana.com/docs/k6/latest/set-up/install-k6/), then:
//   k6 run -e BASE=http://<LB_IP> --summary-export=docs/results/k6-read.json scripts/k6-read.js
// Optional: -e PEAK=100 to push harder (default 50 virtual users).
import http from 'k6/http';
import { check, sleep } from 'k6';

const BASE = __ENV.BASE;
const PEAK = Number(__ENV.PEAK || 50);

export const options = {
  stages: [
    { duration: '1m', target: 10 },   // warm up
    { duration: '3m', target: PEAK }, // sustained load
    { duration: '1m', target: 0 },    // ramp down
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],   // < 1% errors
    http_req_duration: ['p(95)<300'], // 95% of requests under 300 ms
  },
};

export function setup() {
  if (!BASE) throw new Error('Set BASE, e.g. -e BASE=http://203.0.113.10');
  const stamp = Date.now();
  const json = { 'content-type': 'application/json' };
  const signup = http.post(`${BASE}/v1/auth/signup`, JSON.stringify({
    organization: `k6 ${stamp}`,
    name: 'k6',
    email: `k6+${stamp}@example.com`,
    password: 'Demo-Pass-2026',
  }), { headers: json });
  check(signup, { 'signup 201': (r) => r.status === 201 });
  const token = signup.json('token');
  const auth = { headers: { ...json, authorization: `Bearer ${token}` } };
  for (let i = 0; i < 25; i++) {
    http.post(`${BASE}/v1/contacts`, JSON.stringify({
      firstName: `F${i}`,
      lastName: `L${i}`,
      companyName: 'Acme',
      workEmail: `c${i}@example.com`,
    }), auth);
  }
  return { token };
}

export default function (data) {
  const res = http.get(`${BASE}/v1/contacts?q=F1`, {
    headers: { authorization: `Bearer ${data.token}` },
    tags: { name: 'GET /v1/contacts' },
  });
  check(res, { 'status 200': (r) => r.status === 200 });
  sleep(0.5);
}
