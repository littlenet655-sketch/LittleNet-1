from datetime import date
from database.connection import fetch_one, fetch_all, execute

# ─── Age helpers ──────────────────────────────────────────────────────────────

def _age_from_profile_or_user(cid):
    """Return the best available child age without silently inventing one."""
    r = fetch_one(
        '''SELECT cp.date_of_birth, cp.age AS profile_age, u.age AS user_age
           FROM users u
           LEFT JOIN child_profiles cp ON cp.child_id=u.user_id
           WHERE u.user_id=%s''',
        (cid,)
    )
    if not r:
        return None
    dob = r.get('date_of_birth')
    if dob:
        t = date.today()
        return t.year - dob.year - ((t.month, t.day) < (dob.month, dob.day))
    for key in ('profile_age', 'user_age'):
        try:
            value = int(r.get(key))
            if 4 <= value <= 18:
                return value
        except (TypeError, ValueError):
            pass
    return None


def age_group(cid):
    """Map a child to the quiz/feed age bands used by LittleNet."""
    a = _age_from_profile_or_user(cid)
    if a is None:
        return '9-11'  # conservative middle-band fallback for legacy demo rows
    if a <= 8:
        return '6-8'
    if a <= 11:
        return '9-11'
    if a <= 13:
        return '12-13'
    return '14-18'


def learning_age_group(cid):
    return age_group(cid) or '9-11'


def needs_onboarding_quiz(cid, required_questions=2):
    """New parent-created child accounts complete a short age-matched quiz first."""
    created = fetch_one(
        "SELECT 1 FROM activity_logs WHERE child_id=%s AND activity_type='ACCOUNT_CREATED_BY_PARENT' LIMIT 1",
        (cid,)
    )
    if not created:
        return False
    row = fetch_one('SELECT COUNT(*) AS n FROM child_quiz_attempts WHERE child_id=%s', (cid,)) or {'n': 0}
    return int(row.get('n') or 0) < int(required_questions)

# ─── Classic quiz bank (used by quiz page) ────────────────────────────────────

def quizzes(cid, limit=5):
    """Return random unseen age-matched questions; repeat only after exhaustion."""
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
        rows = fetch_all(
            'SELECT * FROM quizzes WHERE age_group=%s ORDER BY RANDOM() LIMIT %s',
            (g, limit)
        )
    return rows

# ─── Feed quiz — single unseen question injected between reels ────────────────

def next_feed_quiz(cid):
    """Return ONE unseen question, preferring personalized/adaptive material."""
    g = age_group(cid)
    if not g:
        return None

    try:
        p_row = fetch_one('''
            SELECT q.*, p.pool_id FROM child_personalized_quiz_pool p
            JOIN quizzes q ON q.quiz_id = p.quiz_id
            WHERE p.child_id = %s AND p.served = FALSE
              AND q.age_group=%s
              AND q.quiz_id NOT IN (SELECT quiz_id FROM child_quiz_attempts WHERE child_id=%s)
            ORDER BY p.created_at ASC LIMIT 1
        ''', (cid, g, cid))
        if p_row:
            execute('UPDATE child_personalized_quiz_pool SET served=TRUE WHERE pool_id=%s', (p_row['pool_id'],))
            return p_row
    except Exception:
        pass

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
    """Record an age-authorized feed answer and award XP."""
    q = fetch_one('SELECT * FROM quizzes WHERE quiz_id=%s', (quiz_id,))
    if not q or q.get('age_group') != age_group(cid):
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

    if q.get('vocabulary_word') and q.get('language'):
        try:
            from quiz.learning_service import record_vocabulary_attempt
            record_vocabulary_attempt(cid, q['vocabulary_word'], q['language'], is_correct)
        except Exception:
            pass

    reset(cid)
    explanation = q.get('explanation') or ''
    return is_correct, q['correct_answer'], xp, explanation

# ─── Post-counter helpers ──────────────────────────────────────────────────────

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
