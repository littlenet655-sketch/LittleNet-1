import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '10s', target: 5 },  // 5 VUs for 10s
    { duration: '15s', target: 10 }, // 10 VUs for 15s
    { duration: '5s', target: 0 },   // ramp-down
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'], // < 5% error rate
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:5000';
const TOKEN = __ENV.TOKEN || 'eyJ1aWQiOjM4LCJyb2xlIjoiQ0hJTEQiLCJuYW1lIjoiQ2hpbGQgQWNjZXB0YW5jZSBBIn0.aqPb3g.PI-RBZSfcoQWVJewQt8AF9ynCZY';

const headers = {
  'Authorization': `Bearer ${TOKEN}`,
  'Content-Type': 'application/json',
};

export default function () {
  // 1. Health check (unauthenticated)
  const resHealth = http.get(`${BASE_URL}/healthz`);
  check(resHealth, { 'healthz status is 200': (r) => r.status === 200 });

  // 2. Mobile Health
  const resMobHealth = http.get(`${BASE_URL}/api/mobile/v1/health`);
  check(resMobHealth, { 'mobile health status is 200': (r) => r.status === 200 });

  // 3. Profile metadata
  const resProfile = http.get(`${BASE_URL}/api/mobile/v1/kids/profile`, { headers });
  check(resProfile, { 'profile status is 200': (r) => r.status === 200 });

  // 4. Feed metadata
  const resFeed = http.get(`${BASE_URL}/api/mobile/v2/kids/feed?cursor=0&limit=10`, { headers });
  check(resFeed, { 'feed status is 200': (r) => r.status === 200 });

  // 5. Reels metadata
  const resReels = http.get(`${BASE_URL}/api/mobile/v1/kids/reels?limit=10`, { headers });
  check(resReels, { 'reels status is 200': (r) => r.status === 200 });

  // 6. Notifications
  const resNotif = http.get(`${BASE_URL}/api/mobile/v1/kids/notifications`, { headers });
  check(resNotif, { 'notifications status is 200': (r) => r.status === 200 });

  // 7. Chat GET
  const resChat = http.get(`${BASE_URL}/api/mobile/v1/kids/chat/40?limit=10`, { headers });
  check(resChat, { 'chat status is 200': (r) => r.status === 200 });

  // 8. Discover metadata
  const resDiscover = http.get(`${BASE_URL}/api/mobile/v2/kids/discover`, { headers });
  check(resDiscover, { 'discover status is 200': (r) => r.status === 200 });

  sleep(0.5);
}
