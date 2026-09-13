import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { routes } from '../src/api/client';
import { childNextRoute, screenForGate } from '../src/navigation/gates';

describe('onboarding navigation', () => {
  it('orders child gates face -> quiz -> home', () => {
    assert.equal(childNextRoute(true, true), 'FaceEnroll');
    assert.equal(childNextRoute(false, true), 'Quiz');
    assert.equal(childNextRoute(false, false), 'KidsHome');
  });

  it('routes backend gates to their resolving screens', () => {
    assert.equal(screenForGate('face'), 'FaceEnroll');
    assert.equal(screenForGate('quiz'), 'Quiz');
    assert.equal(screenForGate('parent_verification'), 'OtpVerify');
    assert.equal(screenForGate('email_verification'), 'OtpVerify');
    assert.equal(screenForGate('quiet_hours'), null);
    assert.equal(screenForGate('screen_time'), null);
  });

  it('prefers v2 routes where a v2 contract exists', () => {
    assert.ok(routes.feedV2.startsWith('/api/mobile/v2/'));
    assert.ok(routes.reelsV2.startsWith('/api/mobile/v2/'));
    assert.ok(routes.discoverV2.startsWith('/api/mobile/v2/'));
    assert.ok(routes.uploadSession.startsWith('/api/mobile/v2/'));
    assert.equal(routes.processingStatus(42), '/api/mobile/v2/posts/42/processing-status');
    assert.equal(routes.uploadComplete('up 1/2'), '/api/mobile/v2/uploads/up%201%2F2/complete');
  });
});
