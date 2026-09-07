"""LittleNet content search.

Search stays inside PostgreSQL so the existing Neon database remains the only
stateful dependency. Results always apply the same child safety boundaries as
the feed: approved/safe content, age/category controls, ACTIVE friendships, and
block/mute rules. Approved comments can make a post discoverable by text, but a
comment can never make an otherwise-invisible post visible.
"""
from urllib.parse import quote_plus

from flask import Blueprint, jsonify, render_template, request, session

from child.service import (
    discoverable_children,
    is_following,
    is_follow_pending,
)
from database.connection import fetch_all, fetch_one
from decorators import child_required
from extensions import limiter
from safety.pii_service import scan_pii
from services.controls import effective_categories, feature_allowed, quiet_hours_state
from services.social import _age_group


content_search_bp = Blueprint("content_search", __name__)


@content_search_bp.before_app_request
def enforce_child_media_runtime_controls():
    """Do not let a known /uploads URL bypass live Parent Mode locks.

    app.py intentionally performs object-level visibility checks for media. This
    global blueprint hook adds the dynamic account/quiet-hours/time/quiz/feature
    gates before that media route runs, so copying a media URL cannot sidestep a
    parent pause or disabled Reels/Stories/Messages surface.
    """
    if session.get('role') != 'CHILD' or not request.path.startswith('/uploads/'):
        return None
    uid = session.get('user_id')
    if not uid:
        return ('Unauthorized', 401)

    user = fetch_one("SELECT account_status FROM users WHERE user_id=%s AND role='CHILD'", (uid,))
    if not user or user.get('account_status') != 'ACTIVE':
        session.clear()
        return ('Account access disabled', 401)

    quiet = quiet_hours_state(uid)
    if quiet.get('active'):
        return ('Media unavailable during quiet hours', 403)

    from services.usage import lock_state
    locked, _ = lock_state(uid)
    if locked:
        return ('Daily screen-time limit reached', 403)

    from quiz.service import quiz_due
    if quiz_due(uid):
        return ('Complete the required learning break before continuing', 403)

    stored = 'uploads/' + request.path[len('/uploads/'):]
    post = fetch_one(
        'SELECT is_reel,is_story FROM posts WHERE media_path=%s OR story_music_path=%s LIMIT 1',
        (stored, stored),
    )
    if post:
        if post.get('is_reel') and not feature_allowed(uid, 'reels'):
            return ('Reels are disabled by Parent Mode', 403)
        if post.get('is_story') and not feature_allowed(uid, 'stories'):
            return ('Stories are disabled by Parent Mode', 403)

    message = fetch_one('SELECT 1 FROM child_messages WHERE media_path=%s LIMIT 1', (stored,))
    if message and not feature_allowed(uid, 'messaging'):
        return ('Messaging is disabled by Parent Mode', 403)
    return None


def _clean_query(value):
    """Normalize user search text without changing its meaning."""
    value = " ".join(str(value or "").strip().split())[:80]
    return value.lstrip("#").strip()


def _like_pattern(value):
    """Create a literal ILIKE contains pattern using ! as the escape char."""
    value = str(value or "").replace("!", "!!").replace("%", "!%").replace("_", "!_")
    return f"%{value}%"


def _scope_params(viewer_id):
    return effective_categories(viewer_id), _age_group(viewer_id)


def search_visible_posts(viewer_id, query, limit=50):
    """Return safe visible posts ranked by caption/hashtag/comment relevance."""
    clean = _clean_query(query)
    if not clean:
        return browse_visible_posts(viewer_id, min(limit, 30))

    cats, age_group = _scope_params(viewer_id)
    word_pattern = _like_pattern(clean)
    tag_pattern = _like_pattern("#" + clean)
    limit = max(1, min(int(limit), 50))

    return fetch_all(
        """WITH search_input AS (
              SELECT %s::text AS clean, %s::text AS word_pattern, %s::text AS tag_pattern
            ), hidden_commenters AS (
              SELECT blocked_id AS user_id FROM blocked_users WHERE blocker_id=%s
              UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
              UNION SELECT muted_id FROM muted_users WHERE muter_id=%s
            ), matching_comments AS (
              SELECT DISTINCT ON (c.post_id) c.post_id,c.comment_text
              FROM comments c
              CROSS JOIN search_input s
              LEFT JOIN hidden_commenters h ON h.user_id=c.child_id
              WHERE c.moderation_status='ALLOWED' AND h.user_id IS NULL
                AND (
                  c.comment_text ILIKE s.word_pattern ESCAPE '!'
                  OR c.comment_text ILIKE s.tag_pattern ESCAPE '!'
                  OR to_tsvector('simple',COALESCE(c.comment_text,''))
                     @@ websearch_to_tsquery('simple',s.clean)
                )
              ORDER BY c.post_id,c.created_at DESC
            )
            SELECT p.*,u.full_name,u.username,cp.profile_picture,
              mc.comment_text AS matched_comment,
              (
                CASE WHEN COALESCE(p.caption,'') ILIKE s.tag_pattern ESCAPE '!' THEN 12 ELSE 0 END +
                CASE WHEN COALESCE(p.caption,'') ILIKE s.word_pattern ESCAPE '!' THEN 8 ELSE 0 END +
                CASE WHEN mc.post_id IS NOT NULL THEN 6 ELSE 0 END +
                CASE WHEN COALESCE(p.content_category,'') ILIKE s.word_pattern ESCAPE '!' THEN 3 ELSE 0 END +
                CASE WHEN COALESCE(u.username,'') ILIKE s.word_pattern ESCAPE '!' THEN 3 ELSE 0 END +
                CASE WHEN COALESCE(u.full_name,'') ILIKE s.word_pattern ESCAPE '!' THEN 2 ELSE 0 END
              ) AS search_score
            FROM posts p
            JOIN users u ON u.user_id=p.child_id
            LEFT JOIN child_profiles cp ON cp.child_id=p.child_id
            LEFT JOIN matching_comments mc ON mc.post_id=p.post_id
            CROSS JOIN search_input s
            WHERE p.moderation_status='ALLOWED' AND p.is_safe=TRUE AND p.is_story=FALSE
              AND p.content_category=ANY(%s)
              AND (%s IS NULL OR p.audience_age_group='ALL' OR p.audience_age_group=%s)
              AND (p.child_id=%s OR EXISTS(
                SELECT 1 FROM followers f
                WHERE f.child_id=%s AND f.following_child_id=p.child_id
                  AND f.approved=TRUE AND f.approval_stage='ACTIVE'))
              AND p.child_id NOT IN (
                SELECT blocked_id FROM blocked_users WHERE blocker_id=%s
                UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
                UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)
              AND (
                COALESCE(p.caption,'') ILIKE s.word_pattern ESCAPE '!'
                OR COALESCE(p.caption,'') ILIKE s.tag_pattern ESCAPE '!'
                OR COALESCE(p.content_category,'') ILIKE s.word_pattern ESCAPE '!'
                OR COALESCE(u.full_name,'') ILIKE s.word_pattern ESCAPE '!'
                OR COALESCE(u.username,'') ILIKE s.word_pattern ESCAPE '!'
                OR mc.post_id IS NOT NULL
                OR to_tsvector('simple',
                    COALESCE(p.caption,'') || ' ' || COALESCE(p.content_category,'') || ' ' ||
                    COALESCE(u.full_name,'') || ' ' || COALESCE(u.username,''))
                   @@ websearch_to_tsquery('simple',s.clean)
              )
            ORDER BY search_score DESC,p.created_at DESC
            LIMIT %s""",
        (
            clean,
            word_pattern,
            tag_pattern,
            viewer_id,
            viewer_id,
            viewer_id,
            cats,
            age_group,
            age_group,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            limit,
        ),
    )


def browse_visible_posts(viewer_id, limit=30):
    """Safe Explore results when no search term is entered."""
    cats, age_group = _scope_params(viewer_id)
    return fetch_all(
        """SELECT p.*,u.full_name,u.username,cp.profile_picture,NULL::text AS matched_comment,0 AS search_score
           FROM posts p
           JOIN users u ON u.user_id=p.child_id
           LEFT JOIN child_profiles cp ON cp.child_id=p.child_id
           WHERE p.moderation_status='ALLOWED' AND p.is_safe=TRUE AND p.is_story=FALSE
             AND p.content_category=ANY(%s)
             AND (%s IS NULL OR p.audience_age_group='ALL' OR p.audience_age_group=%s)
             AND (p.child_id=%s OR EXISTS(
               SELECT 1 FROM followers f
               WHERE f.child_id=%s AND f.following_child_id=p.child_id
                 AND f.approved=TRUE AND f.approval_stage='ACTIVE'))
             AND p.child_id NOT IN (
               SELECT blocked_id FROM blocked_users WHERE blocker_id=%s
               UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
               UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)
           ORDER BY p.created_at DESC LIMIT %s""",
        (
            cats,
            age_group,
            age_group,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            max(1, min(int(limit), 50)),
        ),
    )


def visible_hashtags(viewer_id, query="", limit=6):
    """Extract real hashtags from visible captions and approved visible comments."""
    clean = _clean_query(query).lower()
    pattern = _like_pattern(clean)
    cats, age_group = _scope_params(viewer_id)
    limit = max(1, min(int(limit), 10))

    return fetch_all(
        """WITH hidden_commenters AS (
              SELECT blocked_id AS user_id FROM blocked_users WHERE blocker_id=%s
              UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
              UNION SELECT muted_id FROM muted_users WHERE muter_id=%s
            ), visible_posts AS (
              SELECT p.post_id,p.caption
              FROM posts p
              WHERE p.moderation_status='ALLOWED' AND p.is_safe=TRUE AND p.is_story=FALSE
                AND p.content_category=ANY(%s)
                AND (%s IS NULL OR p.audience_age_group='ALL' OR p.audience_age_group=%s)
                AND (p.child_id=%s OR EXISTS(
                  SELECT 1 FROM followers f
                  WHERE f.child_id=%s AND f.following_child_id=p.child_id
                    AND f.approved=TRUE AND f.approval_stage='ACTIVE'))
                AND p.child_id NOT IN (
                  SELECT blocked_id FROM blocked_users WHERE blocker_id=%s
                  UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
                  UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)
            ), tag_rows AS (
              SELECT LOWER(m[1]) AS tag,vp.post_id
              FROM visible_posts vp
              CROSS JOIN LATERAL regexp_matches(COALESCE(vp.caption,''),'#([[:alnum:]_]{2,50})','g') AS m
              UNION ALL
              SELECT LOWER(m[1]) AS tag,c.post_id
              FROM comments c
              JOIN visible_posts vp ON vp.post_id=c.post_id
              LEFT JOIN hidden_commenters h ON h.user_id=c.child_id
              CROSS JOIN LATERAL regexp_matches(COALESCE(c.comment_text,''),'#([[:alnum:]_]{2,50})','g') AS m
              WHERE c.moderation_status='ALLOWED' AND h.user_id IS NULL
            )
            SELECT tag,COUNT(DISTINCT post_id)::int AS post_count
            FROM tag_rows
            WHERE (%s='' OR tag ILIKE %s ESCAPE '!')
            GROUP BY tag
            ORDER BY post_count DESC,tag ASC
            LIMIT %s""",
        (
            viewer_id,
            viewer_id,
            viewer_id,
            cats,
            age_group,
            age_group,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            viewer_id,
            clean,
            pattern,
            limit,
        ),
    )


@content_search_bp.route("/discover/search/")
@limiter.limit("60 per minute")
@child_required
def discover_search():
    viewer_id = session["user_id"]
    q = (request.args.get("q") or "").strip()
    if q and scan_pii(q).get("detected"):
        return render_template(
            "discover.html",
            children=[],
            recommended_posts=[],
            trending_hashtags=[],
            search_query="",
            active_tag="",
            pii_warning=True,
        )

    person_term = _clean_query(q) if q and not q.startswith("#") else None
    kids = discoverable_children(viewer_id, person_term, 30)
    for child in kids:
        child["is_following"] = is_following(viewer_id, child["user_id"])
        child["is_pending"] = is_follow_pending(viewer_id, child["user_id"])

    posts = search_visible_posts(viewer_id, q, 50 if q else 30)
    tags = visible_hashtags(viewer_id, "", 6)
    return render_template(
        "discover.html",
        children=kids,
        recommended_posts=posts,
        trending_hashtags=tags,
        search_query=q,
        active_tag=q if q.startswith("#") else "",
        pii_warning=False,
    )


@content_search_bp.route("/api/discover/search-suggestions/")
@limiter.limit("120 per minute")
@child_required
def search_suggestions():
    raw = (request.args.get("q") or "").strip()
    if not raw or scan_pii(raw).get("detected"):
        return jsonify(suggestions=[])

    clean = _clean_query(raw)
    if not clean:
        return jsonify(suggestions=[])

    encoded = quote_plus(raw)
    suggestions = [
        {
            "type": "search",
            "label": f'Search "{raw}"',
            "sub": "Safe posts, captions, hashtags and approved comments",
            "url": f"/discover/search/?q={encoded}",
        }
    ]

    if len(clean) >= 2:
        for tag in visible_hashtags(session["user_id"], clean, 5):
            label = "#" + tag["tag"]
            suggestions.append(
                {
                    "type": "hashtag",
                    "label": label,
                    "sub": f"{tag['post_count']} safe post{'s' if tag['post_count'] != 1 else ''}",
                    "url": f"/discover/search/?q={quote_plus(label)}",
                }
            )

        for post in search_visible_posts(session["user_id"], raw, 3):
            caption = (post.get("caption") or "").strip()
            label = caption[:70] if caption else f"Post by @{post.get('username','friend')}"
            matched_comment = (post.get("matched_comment") or "").strip()
            sub = (
                f"Comment match: {matched_comment[:70]}"
                if matched_comment and clean.lower() not in caption.lower()
                else f"@{post.get('username','friend')} · safe post"
            )
            suggestions.append(
                {
                    "type": "post",
                    "label": label,
                    "sub": sub,
                    "url": f"/post/{post['post_id']}/",
                }
            )

    if not raw.startswith("#"):
        for child in discoverable_children(session["user_id"], clean, 5):
            suggestions.append(
                {
                    "type": "user",
                    "label": child["full_name"],
                    "sub": f"@{child['username']} · {child.get('recommendation_reason','Allowed network')}",
                    "url": f"/child/view-profile/{child['user_id']}/",
                }
            )

    return jsonify(suggestions=suggestions[:12])
