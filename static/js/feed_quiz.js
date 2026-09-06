/**
 * LittleNet compulsory doom-scroll break.
 *
 * Home + Reels count viewed items in the browser. After the threshold is hit,
 * scrolling is locked and an age-matched quiz must be answered before the child
 * can continue. The server owns the question age band, answer validation and XP.
 */

const FeedQuiz = (() => {
  const QUIZ_INTERVAL = 4;
  let postsSinceLastQuiz = 0;
  let currentQuizId = null;
  let quizAnswered = false;
  let gateOpen = false;
  let previousOverflow = '';

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

  /** Call whenever a feed/reel item becomes substantially visible. */
  function onPostViewed() {
    if (gateOpen) return;
    postsSinceLastQuiz++;
    if (postsSinceLastQuiz >= QUIZ_INTERVAL) {
      postsSinceLastQuiz = 0;
      _showQuizGate();
    }
  }

  async function _showQuizGate() {
    if (gateOpen) return;
    _lockScroll();
    try {
      const res = await fetch('/api/feed-quiz/', { credentials: 'same-origin' });
      if (!res.ok) throw new Error('quiz unavailable');
      const data = await res.json();
      if (!data.available) throw new Error('no quiz available');
      currentQuizId = data.quiz_id;
      quizAnswered = false;
      _injectBlockingCard(data);
    } catch (e) {
      // Safety/product rule: the intervention is compulsory. If the quiz service
      // cannot supply a question, keep the gate closed and offer only Retry.
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

  function _injectRetryGate() {
    const overlay = _overlayShell();
    const card = document.createElement('div');
    card.className = 'feed-quiz-card fq-visible';
    card.style.cssText = 'width:min(520px,100%);background:#fff;border-radius:24px;padding:24px;box-shadow:0 28px 70px rgba(0,0,0,.28);';
    card.innerHTML = `
      <div class="fq-header"><span class="fq-badge">🧠 Brain Break</span></div>
      <p class="fq-question">Your next age-based quiz is loading. Answer it to continue scrolling.</p>
      <button type="button" class="fq-option fq-retry" style="width:100%;">Retry quiz</button>
    `;
    overlay.appendChild(card);
    card.querySelector('.fq-retry').addEventListener('click', () => {
      overlay.remove();
      // Keep scroll locked while fetching again.
      gateOpen = false;
      _showQuizGate();
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
    quizAnswered = true;
    card.querySelectorAll('.fq-option').forEach(b => { b.disabled = true; b.classList.add('fq-disabled'); });
    card.querySelectorAll('.fq-option').forEach(b => { if (b.dataset.answer === answer) b.classList.add('fq-selected'); });

    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content || '';
      const res = await fetch('/api/feed-quiz/answer/', {
        method: 'POST', credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': csrf },
        body: JSON.stringify({ quiz_id: data.quiz_id, answer }),
      });
      if (!res.ok) throw new Error('answer rejected');
      const result = await res.json();

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

      // Any submitted answer satisfies the intervention; XP is awarded only for correct answers.
      setTimeout(() => { overlay.remove(); _unlockScroll(); }, result.explanation ? 2800 : 1800);
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
    const seen = new WeakSet();
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(e => {
        if (e.isIntersecting && e.intersectionRatio >= .65 && !seen.has(e.target)) {
          seen.add(e.target); onPostViewed();
        }
      });
    }, { threshold: [0.65] });
    document.querySelectorAll('.ig-post, .reel:not(.feed-quiz-reel)').forEach(el => observer.observe(el));
    const mo = new MutationObserver(mutations => {
      mutations.forEach(m => m.addedNodes.forEach(n => {
        if (n.nodeType === 1) {
          if (n.matches?.('.ig-post, .reel:not(.feed-quiz-reel)')) observer.observe(n);
          n.querySelectorAll?.('.ig-post, .reel:not(.feed-quiz-reel)').forEach(el => observer.observe(el));
        }
      }));
    });
    const feed = document.querySelector('.ig-feed, .feed, .reels-page, #reels-container');
    if (feed) mo.observe(feed, { childList:true, subtree:true });
  }

  return { init, onPostViewed };
})();

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', FeedQuiz.init);
else FeedQuiz.init();
