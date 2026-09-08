"""Safe personalized ranking for LittleNet's dedicated Kids feed.

Merges social graph candidates with safe curated educational content.
Never returns an empty feed solely because the child has zero approved social connections.
"""
from __future__ import annotations

from typing import Any

from database.connection import fetch_all, fetch_one
from services.controls import EDUCATIONAL_CATEGORIES, effective_categories
from services.curated_feed import (
    apply_category_diversity,
    fetch_curated_candidates,
    merge_candidates,
    normalize_curated_item,
    normalize_social_item,
)
from services.social import _age_group


def _profile_terms(cid: int) -> tuple[list[str], str]:
    rows = fetch_all(
        """SELECT value FROM (
             SELECT skill_name AS value FROM child_skills WHERE child_id = %s AND approved = TRUE
             UNION SELECT interest_name FROM child_interests WHERE child_id = %s AND approved = TRUE
             UNION SELECT ambition_name FROM child_ambitions WHERE child_id = %s AND approved = TRUE
           ) x""",
        (cid, cid, cid),
    )
    terms = [str(r["value"]).strip() for r in rows if r.get("value")]
    profile = fetch_one("SELECT bio, current_class FROM child_profiles WHERE child_id = %s", (cid,)) or {}
    context = " ".join(terms + [str(profile.get("bio") or ""), str(profile.get("current_class") or "")]).strip()
    return terms, context or "safe educational and age appropriate content"


def candidates(cid: int, cap: int = 60, surface: str = "FEED") -> list[dict[str, Any]]:
    """Retrieve combined candidates from social connections and curated catalog independently.

    A child with zero social connections will receive curated LittleNet content rather
    than experiencing empty-feed starvation.
    """
    cats = effective_categories(cid)
    age_group = _age_group(cid)

    # Reuse the exact child-discovery boundary instead of building a wider
    # recommendation-only graph. Recommendations must never reveal children the
    # viewer could not otherwise discover under Parent Mode policy.
    from child.service import discoverable_child_ids

    allowed_child_ids = discoverable_child_ids(cid)
    if not allowed_child_ids:
        social_rows = []
    else:
        is_reel = str(surface).upper() == "REELS"
        social_rows = fetch_all(
            """SELECT p.*,u.full_name,cp.profile_picture,
                (SELECT COUNT(*) FROM likes l WHERE l.post_id=p.post_id) likes,
                (SELECT COUNT(*) FROM comments c WHERE c.post_id=p.post_id AND c.moderation_status='ALLOWED') comments_count,
                EXISTS(SELECT 1 FROM followers f WHERE f.approved=TRUE AND f.approval_stage='ACTIVE'
                  AND ((f.child_id=%s AND f.following_child_id=p.child_id) OR (f.child_id=p.child_id AND f.following_child_id=%s))) is_following
              FROM posts p JOIN users u ON u.user_id=p.child_id LEFT JOIN child_profiles cp ON cp.child_id=p.child_id
              WHERE p.moderation_status='ALLOWED' AND p.is_safe=TRUE AND p.is_story=FALSE AND p.is_reel=%s
                AND p.child_id=ANY(%s)
                AND p.content_category=ANY(%s)
                AND (%s IS NULL OR p.audience_age_group='ALL' OR p.audience_age_group=%s)
                AND p.child_id<>%s
                AND p.child_id NOT IN (
                  SELECT blocked_id FROM blocked_users WHERE blocker_id=%s
                  UNION SELECT blocker_id FROM blocked_users WHERE blocked_id=%s
                  UNION SELECT muted_id FROM muted_users WHERE muter_id=%s)
              ORDER BY p.created_at DESC LIMIT %s""",
            (cid, cid, is_reel, allowed_child_ids, cats, age_group, age_group, cid, cid, cid, cid, cap),
        )

    social_candidates = [normalize_social_item(r) for r in social_rows]
    curated_candidates = fetch_curated_candidates(cid, surface=surface, limit=cap)

    # Both social and curated are normalized to the common feed schema.
    # Provide backward-compatibility keys for legacy callers expecting post-like dicts:
    for item in social_candidates + curated_candidates:
        if "post_id" not in item:
            item["post_id"] = item["source_id"]
        if "content_category" not in item:
            item["content_category"] = item["category"]
        if "media_path" not in item:
            item["media_path"] = item["media_reference"]

    return merge_candidates(social_candidates, curated_candidates)


def _text_for(item: dict[str, Any]) -> str:
    parts = [
        item.get("category"),
        item.get("content_category"),
        item.get("title"),
        item.get("caption"),
        item.get("ranking_metadata", {}).get("author_name") if isinstance(item.get("ranking_metadata"), dict) else None,
        item.get("full_name"),
    ]
    return " ".join(str(p or "") for p in parts)[:500]


def _fallback_score(item: dict[str, Any], terms: list[str]) -> float:
    hay = _text_for(item).lower()
    score = 0.0
    for term in terms:
        if term.lower() in hay:
            score += 3.0

    meta = item.get("ranking_metadata") or {}
    if meta.get("is_following"):
        score += 2.0
    if item.get("category") in EDUCATIONAL_CATEGORIES or item.get("content_category") in EDUCATIONAL_CATEGORIES:
        score += 1.0
    if item.get("source_type") == "CURATED":
        score += float(meta.get("editorial_weight") or 1.0)
    score += min(float(meta.get("likes") or item.get("likes") or 0), 100.0) / 100.0
    return score


def rank_candidates(cid: int, rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not rows:
        return []
    terms, profile_text = _profile_terms(cid)
    ai_scores: dict[int, float] = {}
    try:
        from safety import remote_client

        if remote_client.enabled():
            ranked = remote_client.rank_texts(
                profile_text,
                [{"id": p.get("source_id", p.get("post_id")), "text": _text_for(p)} for p in rows],
            )
            ai_scores = {int(x["id"]): float(x["score"]) for x in ranked}
        else:
            from safety.semantic_service import rank_texts

            scores = rank_texts(profile_text, [_text_for(p) for p in rows])
            ai_scores = {int(p.get("source_id", p.get("post_id"))): float(score) for p, score in zip(rows, scores)}
    except Exception:
        # Personalization is not a safety gate. Safe deterministic ranking remains available.
        ai_scores = {}

    return sorted(
        rows,
        key=lambda p: (
            ai_scores.get(int(p.get("source_id", p.get("post_id"))), -2.0),
            _fallback_score(p, terms),
            p.get("ranking_metadata", {}).get("created_at") or p.get("created_at") or "",
        ),
        reverse=True,
    )


def apply_diversity_and_balance(ranked_items: list[dict[str, Any]], max_consecutive: int = 2) -> list[dict[str, Any]]:
    """Enforces category diversity and guarantees educational balance in Kids feed."""
    return apply_category_diversity(ranked_items, max_consecutive=max_consecutive)


def personalized_posts(cid: int, limit: int = 30, offset: int = 0) -> list[dict[str, Any]]:
    rows = candidates(cid, max(60, limit + offset + 20))
    ranked = rank_candidates(cid, rows)
    balanced = apply_diversity_and_balance(ranked)
    return balanced[offset : offset + limit]
