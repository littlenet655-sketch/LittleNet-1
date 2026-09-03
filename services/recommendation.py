"""Safe personalized ranking for LittleNet's dedicated For You feed."""
from database.connection import fetch_all,fetch_one
from services.controls import effective_categories
from services.social import _age_group


def _profile_terms(cid):
    rows=fetch_all('''SELECT value FROM (\n      SELECT skill_name value FROM child_skills WHERE child_id=%s AND approved=TRUE\n      UNION SELECT interest_name FROM child_interests WHERE child_id=%s AND approved=TRUE\n      UNION SELECT ambition_name FROM child_ambitions WHERE child_id=%s AND approved=TRUE\n    ) x''',(cid,cid,cid))
    terms=[str(r['value']).strip() for r in rows if r.get('value')]
    profile=fetch_one('SELECT bio,current_class FROM child_profiles WHERE child_id=%s',(cid,)) or {}
    context=' '.join(terms+[str(profile.get('bio') or ''),str(profile.get('current_class') or '')]).strip()
    return terms,context or 'safe educational and age appropriate content'


def candidates(cid,cap=60):
    cats=effective_categories(cid);age_group=_age_group(cid)
    return fetch_all('''SELECT p.*,u.full_name,cp.profile_picture,\n        (SELECT COUNT(*) FROM likes l WHERE l.post_id=p.post_id) likes,\n        (SELECT COUNT(*) FROM comments c WHERE c.post_id=p.post_id AND c.moderation_status='ALLOWED') comments_count,\n        EXISTS(SELECT 1 FROM followers f WHERE f.child_id=%s AND f.following_child_id=p.child_id AND f.approved=TRUE) is_following\n      FROM posts p JOIN users u ON u.user_id=p.child_id LEFT JOIN child_profiles cp ON cp.child_id=p.child_id\n      WHERE p.moderation_status='ALLOWED' AND p.is_safe=TRUE AND p.is_story=FALSE AND p.is_reel=FALSE\n        AND p.content_category=ANY(%s)\n        AND (%s IS NULL OR p.audience_age_group='ALL' OR p.audience_age_group=%s)\n        AND p.child_id<>%s\n        AND p.child_id NOT IN (\n          SELECT blocked_id FROM blocked_users WHERE blocker_id=%s\n          UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s\n          UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)\n      ORDER BY p.created_at DESC LIMIT %s''',(cid,cats,age_group,age_group,cid,cid,cid,cid,cap))


def _text_for(post):
    return ' '.join(str(post.get(k) or '') for k in ('content_category','caption','full_name'))[:500]


def _fallback_score(post,terms):
    hay=_text_for(post).lower();score=0.0
    for term in terms:
        if term.lower() in hay:score+=3.0
    if post.get('is_following'):score+=2.0
    if post.get('content_category') in {'Science','Math','Technology','Education','Nature','Books','Coding','General Knowledge'}:score+=0.5
    score+=min(float(post.get('likes') or 0),100.0)/100.0
    return score


def rank_candidates(cid,rows):
    terms,profile_text=_profile_terms(cid)
    ai_scores={}
    try:
        from safety import remote_client
        if remote_client.enabled():
            ranked=remote_client.rank_texts(profile_text,[{'id':p['post_id'],'text':_text_for(p)} for p in rows])
            ai_scores={int(x['id']):float(x['score']) for x in ranked}
        else:
            from safety.semantic_service import rank_texts
            scores=rank_texts(profile_text,[_text_for(p) for p in rows])
            ai_scores={int(p['post_id']):float(score) for p,score in zip(rows,scores)}
    except Exception:
        # Personalization is not a safety gate. A semantic model outage must not\n        # break Kids Mode; safe deterministic ranking remains available.
        ai_scores={}
    return sorted(rows,key=lambda p:(ai_scores.get(int(p['post_id']),-2.0),_fallback_score(p,terms),p.get('created_at')),reverse=True)


def personalized_posts(cid,limit=30,offset=0):
    rows=candidates(cid,max(60,limit+offset+20))
    ranked=rank_candidates(cid,rows)
    return ranked[offset:offset+limit]
