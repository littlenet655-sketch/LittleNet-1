from datetime import date
from database.connection import fetch_one,fetch_all,execute

def age_group(cid):
    r=fetch_one('SELECT date_of_birth FROM child_profiles WHERE child_id=%s',(cid,));
    if not r or not r['date_of_birth']:return None
    d=r['date_of_birth']; t=date.today(); a=t.year-d.year-((t.month,t.day)<(d.month,d.day))
    return '6-8' if 6<=a<=8 else '9-11' if 9<=a<=11 else '12-13' if 12<=a<=13 else None

def quizzes(cid,limit=5):
    g=age_group(cid); return fetch_all('SELECT * FROM quizzes WHERE age_group=%s ORDER BY RANDOM() LIMIT %s',(g,limit)) if g else []
def setting(cid):return fetch_one('SELECT * FROM parent_quiz_settings WHERE child_id=%s',(cid,))
def quiz_due(cid):
    s=setting(cid)
    if not s or not s['mandatory_quiz'] or not quizzes(cid,1):return False
    p=fetch_one('SELECT posts_seen FROM child_quiz_progress WHERE child_id=%s',(cid,)); return bool(p and p['posts_seen']>=s['quiz_frequency'])
def bump(cid):execute('INSERT INTO child_quiz_progress(child_id,posts_seen) VALUES(%s,1) ON CONFLICT(child_id) DO UPDATE SET posts_seen=child_quiz_progress.posts_seen+1,last_updated=NOW()',(cid,))
def reset(cid):execute('INSERT INTO child_quiz_progress(child_id,posts_seen) VALUES(%s,0) ON CONFLICT(child_id) DO UPDATE SET posts_seen=0,last_updated=NOW()',(cid,))

def learning_age_group(cid):
    g=age_group(cid)
    if g:return g
    r=fetch_one('SELECT date_of_birth FROM child_profiles WHERE child_id=%s',(cid,)) or {}
    if r.get('date_of_birth'):
        d=r['date_of_birth'];t=date.today();a=t.year-d.year-((t.month,t.day)<(d.month,d.day))
        if 14<=a<=18:return '14-18'
    return None

def learning_challenges(cid):
    g=learning_age_group(cid)
    if not g:return []
    return fetch_all('''SELECT c.*,a.completed,a.points_awarded,a.completed_at FROM learning_challenges c
      LEFT JOIN learning_challenge_attempts a ON a.challenge_id=c.challenge_id AND a.child_id=%s
      WHERE c.age_group=%s AND c.active=TRUE ORDER BY a.completed NULLS FIRST,c.challenge_id''',(cid,g))

def learning_points(cid):
    row=fetch_one('SELECT COALESCE(SUM(points_awarded),0) points FROM learning_challenge_attempts WHERE child_id=%s',(cid,))
    return int((row or {}).get('points',0) or 0)
