/**
 * LittleNet compulsory doom-scroll break.
 *
 * PostgreSQL owns the view counter and the required quiz latch. The browser only
 * reports concrete post/reel IDs after they become substantially visible. Refresh,
 * new tabs, or JavaScript state resets cannot clear an already-required break.
 */

const FeedQuiz = (() => {
  // Kept as a UI/source-contract fallback only. The authoritative interval is
  // returned by the server and is never counted in browser memory.
  const QUIZ_INTERVAL = 4;
  let currentQuizId = null;
  let quizAnswered = false;
  let gateOpen = false;
  let previousOverflow = '';

  function _csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content || '';
  }

  async function _json(url, options = {}) {
    const res = await fetch(url, { credentials: 'same-origin', ...options });
    let data = {};
    try { data = await res.json(); } catch (_) { data = {}; }
    if (!res.ok) {
      const err = new Error(data.error || `request failed (${res.status})`);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  function _lockScroll() {
    if (gateOpen) return;
    gateOpen = true;
    previousOverflow = document.documentElement.style.overflow || '';
    document.documentElement.style.overflow = 'hidden';
    document.body.style.overflow = 'hidden';
    document.body.classList.add('littlenet-quiz-locked');
  }

  function _unlockScroll() {
    gateOpen = false;
    document.documentElement.style.overflow = previousOverflow;
    document.body.style.overflow = '';
    document.body.classList.remove('littlenet-quiz-locked');
  }

  function _postId(target) {
    const raw = target?.dataset?.postCard || target?.dataset?.doubleLike || target?.dataset?.postId || '';
    const id = Number.parseInt(String(raw), 10);
    return Number.isFinite(id) && id > 0 ? id : null;
  }

  /** Called whenever a real feed/reel item becomes substantially visible. */
  async function onPostViewed(target) {
    if (gateOpen) return;
    const postId = typeof target === 'number' ? target : _postId(target);
    if (!postId) return;

    try {
      const state = await _json('/quiz/api/feed-view/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': _csrf() },
        body: JSON.stringify({ post_id: postId }),
      });
      // The server is authoritative. It may report a smaller parent-configured
      // interval, but it can never be larger than the LittleNet safety default.
      const interval = Number(state.interval || QUIZ_INTERVAL);
      void interval;
      if (state.required) await _showQuizGate();
    } catch (_) {
      // A child must not be able to bypass the intervention by making the view
      // counter endpoint unavailable. Fail closed and offer Retry only.
      _lockScroll();
      _injectRetryGate('LittleNet could not verify your brain-break status. Reconnect and retry to continue.');
    }
  }

  async function _syncRequiredState() {
    try {
      const state = await _json('/quiz/api/feed-quiz/status/');
      if (state.required) await _showQuizGate();
    } catch (_) {
      _lockScroll();
      _injectRetryGate('LittleNet could not verify your brain-break status. Reconnect and retry to continue.');
    }
  }

  async function _showQuizGate() {
    _lockScroll();
    await _loadRequiredQuiz();
  }

  async function _loadRequiredQuiz() {
    try {
      const data = await _json('/quiz/api/feed-quiz/');
      if (!data.available || !data.required) throw new Error('no required quiz available');
      currentQuizId = data.quiz_id;
      quizAnswered = false;
      _injectBlockingCard(data);
    } catch (_) {
      // Safety/product rule: the intervention is compulsory. If the quiz service
      // cannot supply the required question, keep the gate closed and offer Retry.
      _injectRetryGate();
    }
  }

  function _overlayShell() {
    document.querySelectorAll('.feed-quiz-lock-overlay').forEach(el => el.remove());
    const overlay = document.createElement('div');
    overlay.className = 'feed-quiz-lock-overlay';
    overlay.setAttribute('role', 'dialog');
    overlay.setAttribute('aria-modal', 'true');
    overlay.setAttribute('aria-label', 'Mandatory brain break');
    overlay.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(15,23,42,.76);backdrop-filter:blur(8px);display:flex;align-items:center;justify-content:center;padding:18px;overflow:auto;';
    document.body.appendChild(overlay);
    return overlay;
  }

  function _injectRetryGate(message = 'Your next age-based quiz is loading. Answer it to continue scrolling.') {
    _lockScroll();
    const overlay = _overlayShell();
    const card = document.createElement('div');
    card.className = 'feed-quiz-card fq-visible';
    card.style.cssText = 'width:min(520px,100%);background:#fff;border-radius:24px;padding:24px;box-shadow:0 28px 70px rgba(0,0,0,.28);';
    card.innerHTML = `
      <div class="fq-header"><span class="fq-badge">🧠 Brain Break</span></div>
      <p class="fq-question">${_escape(message)}</p>
      <button type="button" class="fq-option fq-retry" style="width:100%;">Retry quiz</button>
    `;
    overlay.appendChild(card);
    card.querySelector('.fq-retry').addEventListener('click', async () => {
      card.querySelector('.fq-retry').disabled = true;
      try {
        const state = await _json('/quiz/api/feed-quiz/status/');
        if (!state.required) {
          overlay.remove();
          _unlockScroll();
          return;
        }
        await _loadRequiredQuiz();
      } catch (_) {
        _injectRetryGate('Still unable to verify the compulsory brain break. Please reconnect and retry.');
      }
    });
  }

  function _injectBlockingCard(data) {
    const overlay = _overlayShell();
    const card = document.createElement('div');
    card.className = 'feed-quiz-card fq-visible';
    card.style.cssText = 'width:min(560px,100%);max-height:90vh;overflow:auto;background:#fff;border-radius:24px;padding:24px;box-shadow:0 28px 70px rgba(0,0,0,.28);';

    const emojis = { 'Science':'🔬', 'Math':'➕', 'Riddle':'🧩', 'General Knowledge':'🌍',
      'India Special':'🇮🇳', 'Fun Fact':'🤩', 'Technology':'💻', 'Coding':'👨‍💻',
      'Internet Safety':'🔐', 'Environment':'🌿', 'Space':'🚀', 'Health':'❤️',
      'Emoji Quiz':'😊', 'Digital Safety':'🛡️', 'Kindness':'💛', 'Digital Etiquette':'🤝',
      'Digital Literacy':'📰', 'Cyber Safety':'🔒' };
    const icon = emojis[data.category] || '❓';

    card.innerHTML = `
      <div class="fq-header">
        <span class="fq-badge">${icon} Mandatory Brain Break</span>
        <span class="fq-xp-badge">+10 XP ⭐</span>
      </div>
      <div class="fq-category">${_escape(data.category)}</div>
      <p class="fq-question">${_escape(data.question)}</p>
      <div class="fq-options" id="fq-options-${data.quiz_id}">
        ${data.options.map(opt => `
          <button class="fq-option" data-answer="${_escape(opt)}" type="button">
            <span class="fq-opt-dot"></span><span>${_escape(opt)}</span>
          </button>
        `).join('')}
      </div>
      <div class="fq-feedback" id="fq-feedback-${data.quiz_id}" hidden></div>
      <div style="margin-top:14px;font-size:12px;font-weight:700;opacity:.72;text-align:center;">Answer to continue Home or Reels.</div>
    `;
    overlay.appendChild(card);

    card.querySelectorAll('.fq-option').forEach(btn => {
      btn.addEventListener('click', () => _submitAnswer(btn.dataset.answer, data, card, overlay));
    });
  }

  async function _submitAnswer(answer, data, card, overlay) {
    if (quizAnswered) return;
    if (Number(data.quiz_id) !== Number(currentQuizId)) return;
    quizAnswered = true;
    card.querySelectorAll('.fq-option').forEach(b => { b.disabled = true; b.classList.add('fq-disabled'); });
    card.querySelectorAll('.fq-option').forEach(b => { if (b.dataset.answer === answer) b.classList.add('fq-selected'); });

    try {
      const result = await _json('/quiz/api/feed-quiz/answer/', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': _csrf() },
        body: JSON.stringify({ quiz_id: data.quiz_id, answer }),
      });

      card.querySelectorAll('.fq-option').forEach(b => {
        if (b.dataset.answer === result.correct_answer) b.classList.add('fq-correct');
        else if (b.dataset.answer === answer && !result.correct) b.classList.add('fq-wrong');
      });

      const fb = card.querySelector(`#fq-feedback-${data.quiz_id}`);
      fb.hidden = false;
      if (result.correct) {
        fb.className = 'fq-feedback fq-feedback-correct';
        fb.innerHTML = `🎉 <b>Correct!</b> +${result.xp || 10} XP earned!${result.bonus_xp ? ` ⚡ Streak bonus: +${result.bonus_xp} XP!` : ''}${result.explanation ? `<div class="fq-explanation">💡 ${_escape(result.explanation)}</div>` : ''}`;
        _confetti(card);
      } else {
        fb.className = 'fq-feedback fq-feedback-wrong';
        fb.innerHTML = `💡 Good try! The correct answer was <b>${_escape(result.correct_answer)}</b>${result.explanation ? `<div class="fq-explanation">📖 ${_escape(result.explanation)}</div>` : ''}`;
      }

      // Any accepted answer satisfies the intervention; XP is awarded only for
      // correct answers. The server has already cleared the PostgreSQL latch.
      setTimeout(() => { overlay.remove(); currentQuizId = null; _unlockScroll(); }, result.explanation ? 2800 : 1800);
    } catch (e) {
      quizAnswered = false;
      card.querySelectorAll('.fq-option').forEach(b => { b.disabled = false; b.classList.remove('fq-disabled'); });
      const fb = card.querySelector(`#fq-feedback-${data.quiz_id}`);
      fb.hidden = false;
      fb.className = 'fq-feedback fq-feedback-wrong';
      fb.textContent = 'Could not submit yet. Please try again — the brain break must be completed to continue.';
    }
  }

  function _confetti(container) {
    for (let i = 0; i < 22; i++) {
      const dot = document.createElement('span');
      dot.className = 'fq-confetti-dot';
      dot.style.cssText = `left:${Math.random()*100}%;width:${6+Math.random()*8}px;height:${6+Math.random()*8}px;animation-delay:${Math.random()*.35}s;animation-duration:${.8+Math.random()*.6}s;`;
      container.appendChild(dot);setTimeout(() => dot.remove(),1800);
    }
  }

  function _escape(str) {
    return String(str ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function init() {
    if (!('IntersectionObserver' in window)) return;
    const selector = '.ig-post, .reel:not(.feed-quiz-reel)';
    const initialTargets = [...document.querySelectorAll(selector)];
    if (!initialTargets.length) return;

    // Catch an obligation latched in another tab before any new view can advance.
    _syncRequiredState();

    const seen = new WeakSet();
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting && e.intersectionRatio >= .65 && !seen.has(e.target)) {
          seen.add(e.target);
          onPostViewed(e.target);
        }
      });
    }, { threshold: [0.65] });
    initialTargets.forEach(el => observer.observe(el));

    const mo = new MutationObserver(mutations => {
      mutations.forEach(m => m.addedNodes.forEach(n => {
        if (n.nodeType === 1) {
          if (n.matches?.(selector)) observer.observe(n);
          n.querySelectorAll?.(selector).forEach(el => observer.observe(el));
        }
      }));
    });
    const feed = document.querySelector('.ig-feed, .feed, .reels-page, #reels-container, .page');
    if (feed) mo.observe(feed, { childList:true, subtree:true });
  }

  return { init, onPostViewed };
})();

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', FeedQuiz.init);
else FeedQuiz.init();
