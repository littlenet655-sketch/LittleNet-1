from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def test_content_search_indexes_captions_hashtags_and_approved_comments():
    source = text("child/search_routes.py")
    assert "p.caption" in source
    assert "comments c" in source
    assert "c.moderation_status='ALLOWED'" in source
    assert "websearch_to_tsquery('simple'" in source
    assert "regexp_matches" in source
    assert "matched_comment" in source


def test_content_search_never_bypasses_child_visibility_policy():
    source = text("child/search_routes.py")
    assert "p.moderation_status='ALLOWED'" in source
    assert "p.is_safe=TRUE" in source
    assert "p.is_story=FALSE" in source
    assert "p.content_category=ANY(%s)" in source
    assert "p.audience_age_group='ALL'" in source
    assert "f.approved=TRUE AND f.approval_stage='ACTIVE'" in source
    assert "hidden_commenters" in source
    assert "blocked_users" in source
    assert "muted_users" in source


def test_discover_uses_real_database_hashtags_not_hardcoded_demo_tags():
    template = text("child/templates/discover.html")
    routes = text("child/search_routes.py")
    assert "trending_hashtags" in template
    assert "visible_hashtags" in routes
    assert "#mrbean" not in template.lower()
    assert "#science" not in template.lower()
    assert "Search captions, #hashtags, comments" in template


def test_search_results_show_media_caption_and_comment_match():
    template = text("child/templates/discover.html")
    assert "p.media_type == 'VIDEO'" in template
    assert "p.caption" in template
    assert "p.matched_comment" in template
    assert "Matched comment" in template


def test_search_suggestions_are_database_backed_and_dom_safe():
    template = text("child/templates/discover.html")
    routes = text("child/search_routes.py")
    assert "/api/discover/search-suggestions/" in template
    assert "search_visible_posts" in routes
    assert "visible_hashtags" in routes
    assert "label.textContent = item.label" in template
    assert "sub.textContent = item.sub" in template
    assert "box.innerHTML" not in template


def test_legacy_discover_navigation_redirects_into_new_search_surface():
    app = text("app.py")
    assert "from child.search_routes import content_search_bp" in app
    assert "content_search_bp,child_bp" in app
    assert "path.startswith(('/discover/','/api/discover/'))" in app
    assert "if path=='/discover/' and request.method=='GET'" in app
    assert "target='/discover/search/'" in app


def test_dbmate_migration_adds_real_postgres_search_indexes():
    migration = text("db/migrations/20260907001500_content_search_indexes.sql")
    assert "CREATE EXTENSION IF NOT EXISTS pg_trgm" in migration
    assert "idx_posts_caption_trgm" in migration
    assert "idx_comments_text_trgm" in migration
    assert "idx_comments_text_fts" in migration
    assert "gin_trgm_ops" in migration
