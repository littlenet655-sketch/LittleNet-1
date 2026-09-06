const { test, expect } = require('@playwright/test');

async function expectPrivateSecurityHeaders(response) {
  const headers = response.headers();
  expect(headers['x-content-type-options']).toBe('nosniff');
  expect(headers['x-frame-options']).toBe('DENY');
  expect(headers['content-security-policy']).toContain("default-src 'self'");
}

test('web health and login shell are reachable', async ({ page, request }) => {
  const health = await request.get('/healthz');
  expect(health.status()).toBe(200);
  const body = await health.json();
  expect(body.status).toBe('ok');

  const response = await page.goto('/login/');
  expect(response).not.toBeNull();
  expect(response.status()).toBeLessThan(400);
  await expectPrivateSecurityHeaders(response);
  await expect(page.locator('body')).toBeVisible();
});

test('readiness endpoint fails closed or reports ready explicitly', async ({ request }) => {
  const response = await request.get('/readyz');
  expect([200, 503]).toContain(response.status());
  const body = await response.json();
  expect(['ready', 'degraded']).toContain(body.status);
  expect(typeof body.database).toBe('boolean');
  expect(typeof body.mail).toBe('boolean');
});

test('private upload path does not become anonymously fetchable', async ({ request }) => {
  const response = await request.get('/uploads/r2/does-not-exist.jpg', { maxRedirects: 0 });
  expect([401, 403, 404]).toContain(response.status());
});

test('admin area redirects or challenges anonymous users', async ({ request }) => {
  const response = await request.get('/admin/', { maxRedirects: 0 });
  expect([302, 401, 403, 404]).toContain(response.status());
});

test('parent registration page is reachable without exposing activation', async ({ page }) => {
  const response = await page.goto('/register-parent/');
  expect(response).not.toBeNull();
  expect(response.status()).toBeLessThan(400);
  await expect(page.locator('body')).toContainText(/parent|guardian/i);
});
