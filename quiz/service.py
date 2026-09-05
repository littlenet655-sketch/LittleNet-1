from datetime import date
from database.connection import fetch_one, fetch_all, execute

# ─── Age helpers ──────────────────────────────────────────────────────────────

def age_group(cid):
    r = fetch_one('SELECT date_of_birth FROM child_profiles WHERE child_id=%s', (cid,))
    if not r or not r['date_of_birth']:
        return '9-11'  # Safe default for children without DOB
    d = r['date_of_birth']; t = date.today()
    a = t.year - d.year - ((t.month, t.day) < (d.month, d.day))
    return '6-8' if 6 <= a <= 8 else '9-11' if 9 <= a <= 11 else '12-13' if 12 <= a <= 13 else '9-11'

def learning_age_group(cid):
    g = age_group(cid)
    if g:
        return g
    return '9-11'  # Default

# ─── Classic quiz bank (used by quiz page) ────────────────────────────────────

def quizzes(cid, limit=5):
    """Return random unseen questions for the quiz page. Falls back to any if all seen."""
    g = age_group(cid)
    if not g:
        return []
    rows = fetch_all(
        '''SELECT * FROM quizzes
           WHERE age_group=%s
             AND quiz_id NOT IN (
                 SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s
             )
           ORDER BY RANDOM() LIMIT %s''',
        (g, cid, limit)
    )
    if not rows:
        # All questions answered — allow repeats so the quiz page never breaks
        rows = fetch_all(
            'SELECT * FROM quizzes WHERE age_group=%s ORDER BY RANDOM() LIMIT %s',
            (g, limit)
        )
    return rows

# ─── Feed quiz — single unseen question injected between reels ────────────────

def next_feed_quiz(cid):
    """Return ONE unseen question for the feed quiz card.
    Prioritizes child_personalized_quiz_pool, then adaptive difficulty, then general bank."""
    g = age_group(cid)
    if not g:
        return None

    # 1. Check personalized pool first
    try:
        p_row = fetch_one('''
            SELECT q.*, p.pool_id FROM child_personalized_quiz_pool p
            JOIN quizzes q ON q.quiz_id = p.quiz_id
            WHERE p.child_id = %s AND p.served = FALSE
              AND q.quiz_id NOT IN (SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s)
            ORDER BY p.created_at ASC LIMIT 1
        ''', (cid, cid))
        if p_row:
            execute('UPDATE child_personalized_quiz_pool SET served=TRUE WHERE pool_id=%s', (p_row['pool_id'],))
            return p_row
    except Exception:
        pass

    # 2. Check adaptive difficulty level
    from quiz.learning_service import get_child_difficulty_level, trigger_background_refill_if_needed, populate_child_personalized_pool
    diff = get_child_difficulty_level(cid)

    row = fetch_one(
        '''SELECT * FROM quizzes
           WHERE age_group=%s AND difficulty_level=%s
             AND quiz_id NOT IN (
                 SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s
             )
           ORDER BY RANDOM() LIMIT 1''',
        (g, diff, cid)
    )
    if not row:
        row = fetch_one(
            '''SELECT * FROM quizzes
               WHERE age_group=%s
                 AND quiz_id NOT IN (
                     SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s
                 )
               ORDER BY RANDOM() LIMIT 1''',
            (g, cid)
        )

    # 3. Fire non-blocking async refill and personalization in background
    try:
        trigger_background_refill_if_needed(g, cid)
        populate_child_personalized_pool(cid, g)
    except Exception:
        pass

    return row

def _unseen_count(cid, g):
    r = fetch_one(
        '''SELECT COUNT(*) AS c FROM quizzes
           WHERE age_group=%s
             AND quiz_id NOT IN (
                 SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s
             )''',
        (g, cid)
    )
    return int((r or {}).get('c', 0))

# ─── Feed quiz answer submission ──────────────────────────────────────────────

def record_feed_answer(cid, quiz_id, selected_answer):
    """Record a feed-quiz answer. Returns (is_correct, correct_answer, xp_awarded, explanation)."""
    q = fetch_one('SELECT * FROM quizzes WHERE quiz_id=%s', (quiz_id,))
    if not q:
        return False, '', 0, ''
    is_correct = (str(selected_answer).strip() == str(q['correct_answer']).strip())
    execute(
        'INSERT INTO child_quiz_attempts(child_id,quiz_id,selected_answer,is_correct) VALUES(%s,%s,%s,%s)',
        (cid, quiz_id, selected_answer, is_correct)
    )
    xp = 10 if is_correct else 0
    if xp:
        execute(
            '''INSERT INTO child_xp(child_id, xp) VALUES(%s,%s)
               ON CONFLICT(child_id) DO UPDATE SET xp=child_xp.xp+EXCLUDED.xp, updated_at=NOW()''',
            (cid, xp)
        )

    # If vocabulary word is attached, update spaced repetition tracking
    if q.get('vocabulary_word') and q.get('language'):
        try:
            from quiz.learning_service import record_vocabulary_attempt
            record_vocabulary_attempt(cid, q['vocabulary_word'], q['language'], is_correct)
        except Exception:
            pass

    # Reset bump counter so next quiz triggers after another 3-4 posts
    reset(cid)
    explanation = q.get('explanation') or ''
    return is_correct, q['correct_answer'], xp, explanation

# ─── Post-counter helpers ─────────────────────────────────────────────────────

def setting(cid):
    return fetch_one('SELECT * FROM parent_quiz_settings WHERE child_id=%s', (cid,))

def quiz_due(cid):
    s = setting(cid)
    if not s or not s['mandatory_quiz'] or not quizzes(cid, 1):
        return False
    p = fetch_one('SELECT posts_seen FROM child_quiz_progress WHERE child_id=%s', (cid,))
    return bool(p and p['posts_seen'] >= s['quiz_frequency'])

def bump(cid):
    execute(
        '''INSERT INTO child_quiz_progress(child_id,posts_seen) VALUES(%s,1)
           ON CONFLICT(child_id) DO UPDATE SET posts_seen=child_quiz_progress.posts_seen+1,last_updated=NOW()''',
        (cid,)
    )

def reset(cid):
    execute(
        '''INSERT INTO child_quiz_progress(child_id,posts_seen) VALUES(%s,0)
           ON CONFLICT(child_id) DO UPDATE SET posts_seen=0,last_updated=NOW()''',
        (cid,)
    )

# ─── Learning challenges ──────────────────────────────────────────────────────

def learning_challenges(cid):
    g = learning_age_group(cid)
    if not g:
        return []
    return fetch_all(
        '''SELECT c.*,a.completed,a.points_awarded,a.completed_at
           FROM learning_challenges c
           LEFT JOIN learning_challenge_attempts a
             ON a.challenge_id=c.challenge_id AND a.child_id=%s
           WHERE c.age_group=%s AND c.active=TRUE
           ORDER BY a.completed NULLS FIRST, c.challenge_id''',
        (cid, g)
    )

def learning_points(cid):
    row = fetch_one(
        'SELECT COALESCE(SUM(points_awarded),0) points FROM learning_challenge_attempts WHERE child_id=%s',
        (cid,)
    )
    return int((row or {}).get('points', 0) or 0)
