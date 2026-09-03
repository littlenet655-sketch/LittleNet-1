from datetime import date
from database.connection import fetch_one,fetch_all,execute

def profile_exists(cid):return bool(fetch_one('SELECT 1 FROM child_profiles WHERE child_id=%s',(cid,)))
def get_child_profile(cid):return fetch_one('SELECT * FROM child_profiles WHERE child_id=%s',(cid,))
def create_child_profile(cid,form):
    m=fetch_one('SELECT parent_id FROM parent_child_map WHERE child_id=%s',(cid,)); dob=form.get('date_of_birth') or None
    execute('''INSERT INTO child_profiles(child_id,parent_id,full_name,date_of_birth,school_name,location,current_class,bio) VALUES(%s,%s,%s,%s,%s,%s,%s,%s) ON CONFLICT(child_id) DO UPDATE SET full_name=EXCLUDED.full_name,date_of_birth=EXCLUDED.date_of_birth,school_name=EXCLUDED.school_name,location=EXCLUDED.location,current_class=EXCLUDED.current_class,bio=EXCLUDED.bio,updated_at=NOW()''',(cid,(m or {}).get('parent_id'),form.get('full_name','').strip(),dob,form.get('school_name'),form.get('location'),form.get('current_class'),form.get('bio')))
def is_following(a,b):return bool(fetch_one('SELECT 1 FROM followers WHERE child_id=%s AND following_child_id=%s AND approved=TRUE',(a,b)))
def is_follow_pending(a,b):return bool(fetch_one('SELECT 1 FROM followers WHERE child_id=%s AND following_child_id=%s AND approved=FALSE',(a,b)))
def follow_child(a,b):execute('INSERT INTO followers(child_id,following_child_id,approved) VALUES(%s,%s,FALSE) ON CONFLICT(child_id,following_child_id) DO NOTHING',(a,b))
def unfollow_child(a,b):execute('DELETE FROM followers WHERE child_id=%s AND following_child_id=%s',(a,b))
def get_random_children(cid):
    # Discover is intentionally not a global child directory. Candidates must be
    # connected to the child's already parent-approved network, share the same
    # non-empty school name, or be another child linked to the same parent.
    return fetch_all('''WITH viewer AS (
          SELECT cp.school_name,pcm.parent_id FROM child_profiles cp
          LEFT JOIN parent_child_map pcm ON pcm.child_id=cp.child_id WHERE cp.child_id=%s
        ), approved_friends AS (
          SELECT following_child_id friend_id FROM followers WHERE child_id=%s AND approved=TRUE
          UNION SELECT child_id FROM followers WHERE following_child_id=%s AND approved=TRUE
        ), network AS (
          SELECT DISTINCT CASE WHEN f.child_id=af.friend_id THEN f.following_child_id ELSE f.child_id END candidate_id
          FROM approved_friends af JOIN followers f ON f.approved=TRUE AND (f.child_id=af.friend_id OR f.following_child_id=af.friend_id)
        )
        SELECT u.user_id,u.full_name,cp.profile_picture,
          CASE WHEN pcm.parent_id=(SELECT parent_id FROM viewer) AND pcm.parent_id IS NOT NULL THEN 'Family'
               WHEN COALESCE(cp.school_name,'')<>'' AND LOWER(cp.school_name)=LOWER(COALESCE((SELECT school_name FROM viewer),'')) THEN 'Same school'
               ELSE 'Approved network' END AS recommendation_reason
        FROM users u JOIN child_profiles cp ON cp.child_id=u.user_id
        LEFT JOIN parent_child_map pcm ON pcm.child_id=u.user_id
        WHERE u.role='CHILD' AND u.account_status='ACTIVE' AND u.user_id<>%s
          AND (u.user_id IN (SELECT candidate_id FROM network)
               OR (COALESCE((SELECT school_name FROM viewer),'')<>'' AND LOWER(cp.school_name)=LOWER((SELECT school_name FROM viewer)))
               OR (pcm.parent_id IS NOT NULL AND pcm.parent_id=(SELECT parent_id FROM viewer)))
          AND u.user_id NOT IN (SELECT blocked_id FROM blocked_users WHERE blocker_id=%s
             UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
             UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)
        ORDER BY CASE WHEN pcm.parent_id=(SELECT parent_id FROM viewer) AND pcm.parent_id IS NOT NULL THEN 0
                      WHEN LOWER(COALESCE(cp.school_name,''))=LOWER(COALESCE((SELECT school_name FROM viewer),'')) AND COALESCE(cp.school_name,'')<>'' THEN 1 ELSE 2 END,
                 u.full_name LIMIT 30''',(cid,cid,cid,cid,cid,cid,cid))

def counts(cid):
 return {'posts':fetch_one("SELECT COUNT(*) n FROM posts WHERE child_id=%s AND is_story=FALSE AND moderation_status='ALLOWED' AND is_safe=TRUE",(cid,))['n'],'followers':fetch_one('SELECT COUNT(*) n FROM followers WHERE following_child_id=%s AND approved=TRUE',(cid,))['n'],'following':fetch_one('SELECT COUNT(*) n FROM followers WHERE child_id=%s AND approved=TRUE',(cid,))['n']}

def replace_profile_tags(cid,skills,interests,ambitions):
    for table in ['child_skills','child_interests','child_ambitions']:
        execute(f'DELETE FROM {table} WHERE child_id=%s',(cid,))
    for value in [x.strip() for x in skills if x.strip()]:
        execute('INSERT INTO child_skills(child_id,skill_name,approved) VALUES(%s,%s,FALSE)',(cid,value))
    for value in [x.strip() for x in interests if x.strip()]:
        execute('INSERT INTO child_interests(child_id,interest_name,approved) VALUES(%s,%s,FALSE)',(cid,value))
    for value in [x.strip() for x in ambitions if x.strip()]:
        execute('INSERT INTO child_ambitions(child_id,ambition_name,approved) VALUES(%s,%s,FALSE)',(cid,value))

def recommended_posts(cid,limit=30,offset=0):
    # Candidate visibility is filtered before semantic ranking. AI personalization
    # can reorder safe posts but can never bypass age/Parent Mode/safety rules.
    from services.recommendation import personalized_posts
    return personalized_posts(cid,limit,offset)
