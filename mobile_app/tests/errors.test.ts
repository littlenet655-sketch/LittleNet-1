import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { gateFor, parseErrorResponse, retryDelayMs, shouldRetryRequest, userMessageFor } from '../src/api/errors';

describe('backend gate parsing', () => {
  it('maps 428 face/quiz codes to gates', () => {
    assert.equal(parseErrorResponse(428, { error: 'face_enrollment_required' }).gate, 'face');
    assert.equal(parseErrorResponse(428, { error: 'quiz_required' }).gate, 'quiz');
    assert.equal(parseErrorResponse(428, { error: 'onboarding_quiz_required' }).gate, 'quiz');
  });

  it('maps 423 lock codes to gates', () => {
    assert.equal(parseErrorResponse(423, { error: 'quiet_hours' }).gate, 'quiet_hours');
    assert.equal(parseErrorResponse(423, { error: 'screen_time_limit' }).gate, 'screen_time');
  });

  it('maps parent verification resume codes', () => {
    const err = parseErrorResponse(428, { error: 'parent_verification_required', pending_token: 'abc' });
    assert.equal(err.gate, 'parent_verification');
    assert.equal(err.details.pending_token, 'abc');
  });

  it('keeps an explicit payload gate field authoritative', () => {
    assert.equal(gateFor(200, 'other', 'face'), 'face');
    assert.equal(gateFor(200, 'other', 'quiz'), 'quiz');
  });

  it('gives explicit UX copy for every gate status family', () => {
    for (const [status, code] of [[401, 'invalid_credentials'], [403, 'disabled_by_parent'], [423, 'quiet_hours'], [428, 'quiz_required'], [503, 'adult_verification_unavailable']] as Array<[number, string]>) {
      const message = userMessageFor(status, code, {});
      assert.ok(message.length > 10, `${status}/${code} needs user-facing copy`);
    }
  });

  it('explains guardian verification retry reasons distinctly', () => {
    assert.match(userMessageFor(422, 'single_face_required', {}), /one face/i);
    assert.match(userMessageFor(422, 'liveness_failed', {}), /blink/i);
    assert.match(userMessageFor(422, 'age_estimate_ambiguous', {}), /confidently/i);
    assert.match(userMessageFor(503, 'age_verification_unavailable', {}), /temporarily/i);
  });

  it('explains face-login failure reasons distinctly', () => {
    const spoof = userMessageFor(401, 'face_login_failed', { reason: 'spoof' });
    const missing = userMessageFor(404, 'face_login_failed', { reason: 'not_enrolled' });
    assert.match(spoof, /Liveness/);
    assert.match(missing, /enroll/i);
  });

  it('retries only safe GET requests with backoff', () => {
    assert.equal(shouldRetryRequest('GET', 0, 503), true);
    assert.equal(shouldRetryRequest('GET', 0, 0), true);
    assert.equal(shouldRetryRequest('POST', 0, 503), false);
    assert.equal(shouldRetryRequest('GET', 2, 503), false);
    assert.equal(shouldRetryRequest('GET', 0, 400), false);
    assert.ok(retryDelayMs(1) <= 4000);
  });
});
