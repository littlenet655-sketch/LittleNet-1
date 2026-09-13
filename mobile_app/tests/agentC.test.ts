import { describe, it } from 'node:test';
import assert from 'node:assert/strict';

process.env.EXPO_PUBLIC_API_BASE_URL = 'https://backend.test.invalid';

import { setUnauthorizedHandler } from '../src/api/client';
import { fetchFeedV2 } from '../src/api/kidsFeed';
import { addComment, toggleLike, toggleSave } from '../src/api/kidsSocial';
import { dedupeFeed, isPubliclyVisible, isTerminalStage, processingStage, shouldLoadReel, shouldPlayReel } from '../src/kids/social';

let seen: Array<{ url: string; init: RequestInit }> = [];
let nextPayload: unknown = { ok: true };
let nextStatus = 200;

function stub() {
  seen = [];
  (globalThis as unknown as Record<string, unknown>).fetch = async (url: unknown, init?: RequestInit) => {
    seen.push({ url: String(url), init: init ?? {} });
    return { ok: nextStatus >= 200 && nextStatus < 300, status: nextStatus, json: async () => nextPayload };
  };
}

describe('agentC feed pagination/dedupe/refresh', () => {
  it('fetches cursor pages and dedupes by source identity', async () => {
    stub();
    setUnauthorizedHandler(null);
    nextStatus = 200;
    nextPayload = { ok: true, items: [{ source_type: 'SOCIAL', source_id: 1, post_id: 1 }], next_cursor: 1, has_more: true, session_id: 's' };
    const page = await fetchFeedV2('tok', 0, 10);
    assert.equal(page.next_cursor, 1);
    assert.ok(seen[0]?.url.includes('/api/mobile/v2/kids/feed?cursor=0'));
    const merged = dedupeFeed([...page.items, ...page.items, { source_type: 'SOCIAL' as const, source_id: 2, post_id: 2 }]);
    assert.equal(merged.length, 2);
  });

  it('like/unlike and save/unsave hit real routes', async () => {
    stub();
    nextStatus = 200;
    nextPayload = { ok: true, liked: true, likes: 4 };
    const like = await toggleLike('tok', 7);
    assert.equal(like.liked, true);
    assert.ok(seen[0]?.url.endsWith('/api/mobile/v1/kids/posts/7/like'));
    nextPayload = { ok: true, saved: true };
    const save = await toggleSave('tok', 7);
    assert.equal(save.saved, true);
  });

  it('comments allow/review/block behavior', async () => {
    stub();
    nextStatus = 200;
    nextPayload = { ok: true, status: 'ALLOWED', comment_id: 1 };
    const ok = await addComment('tok', 7, 'kind words');
    assert.equal(ok.status, 'ALLOWED');
    nextPayload = { ok: true, status: 'REVIEW', comment_id: 2 };
    const review = await addComment('tok', 7, 'maybe');
    assert.equal(review.status, 'REVIEW');
  });

  it('REVIEW/BLOCKED never public; stages stop polling', () => {
    assert.equal(isPubliclyVisible({ moderation_status: 'ALLOWED', is_safe: true }), true);
    assert.equal(isPubliclyVisible({ moderation_status: 'REVIEW', is_safe: true }), false);
    assert.equal(isPubliclyVisible({ moderation_status: 'BLOCKED', is_safe: false }), false);
    assert.equal(processingStage('PROCESSING', 'PENDING'), 'processing');
    assert.equal(processingStage('BLOCKED', 'BLOCKED'), 'blocked');
    assert.equal(isTerminalStage('allowed'), true);
    assert.equal(isTerminalStage('processing'), false);
  });

  it('selects one foreground reel and bounds adjacent loading', () => {
    assert.equal(shouldPlayReel(2, 2, true), true);
    assert.equal(shouldPlayReel(1, 2, true), false);
    assert.equal(shouldPlayReel(2, 2, false), false);
    assert.equal(shouldLoadReel(1, 2), true);
    assert.equal(shouldLoadReel(3, 2), true);
    assert.equal(shouldLoadReel(4, 2), false);
  });
});
