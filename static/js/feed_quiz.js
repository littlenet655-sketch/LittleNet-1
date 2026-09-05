/**
 * LittleNet Feed Quiz — inline quiz card injected between reels.
 * Shows after every 3-4 posts, fetches one unseen question, handles
 * answer submission, animates result (confetti on correct, gentle retry on wrong).
 * No-repeat guaranteed by server — same question never appears twice for a child.
 */

const FeedQuiz = (() => {
  // How many posts between quiz cards (randomised 3-4)
  const QUIZ_INTERVAL_MIN = 3;
  const QUIZ_INTERVAL_MAX = 4;

  let postsSinceLastQuiz = 0;
  let nextQuizAt = _nextInterval();
  let currentQuizId = null;
  let quizAnswered = false;

  function _nextInterval() {
    return Math.floor(Math.random() * (QUIZ_INTERVAL_MAX - QUIZ_INTERVAL_MIN + 1)) + QUIZ_INTERVAL_MIN;
  }

  /** Call this every time a reel/post becomes visible in the feed. */
  function onPostViewed() {
    postsSinceLastQuiz++;
    if (postsSinceLastQuiz >= nextQuizAt) {
      postsSinceLastQuiz = 0;
      nextQuizAt = _nextInterval();
      _showQuizCard();
    }
  }

  async function _showQuizCard() {
    try {
      const res = await fetch('/api/feed-quiz/', { credentials: 'same-origin' });
      if (!res.ok) return;
      const data = await res.json();
      if (!data.available) return;
      currentQuizId = data.quiz_id;
      quizAnswered = false;
      _injectCard(data);
    } catch (e) {
      // Never crash the feed
    }
  }

  function _injectCard(data) {
    // Remove any existing quiz card first
    document.querySelectorAll('.feed-quiz-card').forEach(el => el.remove());

    const card = document.createElement('div');
    card.className = 'feed-quiz-card';
    card.setAttribute('role', 'region');
    card.setAttribute('aria-label', 'Quick quiz');

    const emojis = { 'Science':'🔬', 'Math':'➕', 'Riddle':'🧩', 'General Knowledge':'🌍',
      'India Special':'🇮🇳', 'Fun Fact':'🤩', 'Technology':'💻', 'Coding':'👨‍💻',
      'Internet Safety':'🔐', 'Environment':'🌿', 'Space':'🚀', 'Health':'❤️',
      'Emoji Quiz':'😊', 'Digital Safety':'🛡️', 'Kindness':'💛', 'Digital Etiquette':'🤝',
      'Digital Literacy':'📰', 'Cyber Safety':'🔒' };
    const icon = emojis[data.category] || '❓';

    card.innerHTML = `
      <div class="fq-header">
        <span class="fq-badge">${icon} Brain Break!</span>
        <span class="fq-xp-badge">+10 XP ⭐</span>
      </div>
      <div class="fq-category">${data.category}</div>
      <p class="fq-question">${_escape(data.question)}</p>
      <div class="fq-options" id="fq-options-${data.quiz_id}">
        ${data.options.map(opt => `
          <button class="fq-option" data-answer="${_escape(opt)}" type="button">
            <span class="fq-opt-dot"></span>
            <span>${_escape(opt)}</span>
          </button>
        `).join('')}
      </div>
      <div class="fq-feedback" id="fq-feedback-${data.quiz_id}" hidden></div>
      <div class="fq-skip">
        <button class="fq-skip-btn" type="button">Skip for now →</button>
      </div>
    `;

    // Insert into reels-page as a snap reel, or into .ig-feed after 2nd post
    const reelsPage = document.querySelector('.reels-page');
    if (reelsPage) {
      const reelCard = document.createElement('section');
      reelCard.className = 'reel feed-quiz-reel';
      reelCard.appendChild(card);
      const reels = reelsPage.querySelectorAll('.reel:not(.feed-quiz-reel)');
      if (reels.length >= 2) {
        reels[1].insertAdjacentElement('afterend', reelCard);
      } else {
        reelsPage.appendChild(reelCard);
      }
    } else {
      const feed = document.querySelector('.ig-feed');
      const posts = feed ? feed.querySelectorAll('.ig-post') : [];
      if (posts.length >= 2) {
        posts[1].insertAdjacentElement('afterend', card);
      } else if (feed) {
        feed.appendChild(card);
      } else {
        document.querySelector('main')?.appendChild(card);
      }
    }

    // Animate in
    requestAnimationFrame(() => card.classList.add('fq-visible'));

    // Bind option clicks
    card.querySelectorAll('.fq-option').forEach(btn => {
      btn.addEventListener('click', () => _submitAnswer(btn.dataset.answer, data, card));
    });

    // Skip
    card.querySelector('.fq-skip-btn').addEventListener('click', () => {
      card.classList.add('fq-exit');
      setTimeout(() => {
        const rw = card.closest('.feed-quiz-reel');
        if (rw) rw.remove();
        else card.remove();
      }, 400);
    });
  }

  async function _submitAnswer(answer, data, card) {
    if (quizAnswered) return;
    quizAnswered = true;

    // Disable all buttons
    card.querySelectorAll('.fq-option').forEach(b => { b.disabled = true; b.classList.add('fq-disabled'); });
    // Highlight selected
    card.querySelectorAll('.fq-option').forEach(b => {
      if (b.dataset.answer === answer) b.classList.add('fq-selected');
    });

    try {
      const csrf = document.querySelector('meta[name="csrf-token"]')?.content || '';
      const res = await fetch('/api/feed-quiz/answer/', {
        method: 'POST',
        credentials: 'same-origin',
        headers: { 'Content-Type': 'application/json', 'X-CSRFToken': csrf },
        body: JSON.stringify({ quiz_id: data.quiz_id, answer }),
      });
      const result = await res.json();

      // Show correct/wrong highlight
      card.querySelectorAll('.fq-option').forEach(b => {
        if (b.dataset.answer === result.correct_answer) b.classList.add('fq-correct');
        else if (b.dataset.answer === answer && !result.correct) b.classList.add('fq-wrong');
      });

      const fb = card.querySelector(`#fq-feedback-${data.quiz_id}`);
      fb.hidden = false;

      if (result.correct) {
        fb.className = 'fq-feedback fq-feedback-correct';
        fb.innerHTML = `🎉 <b>Correct!</b> +${result.xp || 10} XP earned!${result.bonus_xp ? ` ⚡ Streak bonus: +${result.bonus_xp} XP!` : ''}${result.explanation ? `<div class="fq-explanation" style="font-size:0.85rem;margin-top:6px;opacity:0.95;">💡 ${_escape(result.explanation)}</div>` : ''}`;
        _confetti(card);
      } else {
        fb.className = 'fq-feedback fq-feedback-wrong';
        fb.innerHTML = `💡 Good try! The correct answer was: <b>${_escape(result.correct_answer)}</b>${result.explanation ? `<div class="fq-explanation" style="font-size:0.85rem;margin-top:6px;opacity:0.95;">📖 ${_escape(result.explanation)}</div>` : ''}`;
      }

      // Auto-dismiss after reading result (slightly longer if explanation is shown)
      const dismissDelay = result.explanation ? 3600 : 2200;
      setTimeout(() => {
        card.classList.add('fq-exit');
        setTimeout(() => {
          const rw = card.closest('.feed-quiz-reel');
          if (rw) rw.remove();
          else card.remove();
        }, 400);
      }, dismissDelay);

    } catch (e) {
      card.querySelectorAll('.fq-option').forEach(b => { b.disabled = false; b.classList.remove('fq-disabled'); });
      quizAnswered = false;
    }
  }

  function _confetti(container) {
    const colours = ['#10B981','#38BDF8','#F59E0B','#EC4899','#818CF8','#34D399'];
    for (let i = 0; i < 28; i++) {
      const dot = document.createElement('span');
      dot.className = 'fq-confetti-dot';
      dot.style.cssText = `
        left:${Math.random() * 100}%;
        background:${colours[Math.floor(Math.random() * colours.length)]};
        width:${6 + Math.random() * 8}px;
        height:${6 + Math.random() * 8}px;
        animation-delay:${Math.random() * 0.4}s;
        animation-duration:${0.8 + Math.random() * 0.6}s;
      `;
      container.appendChild(dot);
      setTimeout(() => dot.remove(), 1800);
    }
  }

  function _escape(str) {
    return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  // Auto-wire to IntersectionObserver on .ig-post and .reel items
  function init() {
    if (!('IntersectionObserver' in window)) return;
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(e => { if (e.isIntersecting) onPostViewed(); });
    }, { threshold: 0.5 });
    // Observe existing feed and reel items
    document.querySelectorAll('.ig-post, .reel:not(.feed-quiz-reel)').forEach(el => observer.observe(el));
    // Observe dynamically added items (infinite scroll)
    const mo = new MutationObserver(mutations => {
      mutations.forEach(m => m.addedNodes.forEach(n => {
        if (n.nodeType === 1) {
          if (n.matches?.('.ig-post, .reel:not(.feed-quiz-reel)')) observer.observe(n);
          n.querySelectorAll?.('.ig-post, .reel:not(.feed-quiz-reel)').forEach(el => observer.observe(el));
        }
      }));
    });
    const feed = document.querySelector('.ig-feed, .feed, .reels-page, #reels-container');
    if (feed) mo.observe(feed, { childList: true, subtree: true });
  }

  return { init, onPostViewed };
})();

// Auto-init when DOM ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', FeedQuiz.init);
} else {
  FeedQuiz.init();
}
