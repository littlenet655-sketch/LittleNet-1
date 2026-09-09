"""
test_phase3_partial_completion.py
Contract tests for Phase 3 partial-screen completion routes.

Screens completed:
  #21 Reel Comments         — GET /kids/posts/<id>/comments
  #13/#19/#24 Preview       — POST /kids/posts/preview
  #25 Reel Share            — GET /kids/posts/<id>/share
  #32 New Message           — GET /kids/contacts
  #34 Block User            — POST /kids/block/<id>
  #34 Report User           — POST /kids/report/user
  #57 Smart Controls GET    — GET /parent/time-limit/<id>
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def test_phase3_new_routes_registered_in_flask_app():
    from app import app
    routes = {rule.rule: set(rule.methods or ()) for rule in app.url_map.iter_rules()}
    required = {
        "/api/mobile/v1/kids/posts/<int:post_id>/comments": {"GET"},
        "/api/mobile/v1/kids/posts/preview": {"POST"},
        "/api/mobile/v1/kids/posts/<int:post_id>/share": {"GET"},
        "/api/mobile/v1/kids/contacts": {"GET"},
        "/api/mobile/v1/kids/block/<int:target_id>": {"POST"},
        "/api/mobile/v1/kids/report/user": {"POST"},
        "/api/mobile/v1/parent/time-limit/<int:child_id>": {"GET"},
    }
    for route, methods in required.items():
        assert route in routes, f"Route not registered: {route}"
        for m in methods:
            assert m in routes[route], f"{route} missing {m}"


def test_get_comments_reads_from_comments_table():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/posts/<int:post_id>/comments"' in api
    assert "FROM comments" in api
    assert "moderation_status" in api


def test_preview_route_never_inserts_to_posts():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/posts/preview"' in api
    preview_block = api.split('"/api/mobile/v1/kids/posts/preview"', 1)[1].split('"/api/mobile/v1/kids/posts/', 1)[0]
    assert "INSERT INTO posts" not in preview_block


def test_share_route_checks_visibility_and_returns_counts():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/posts/<int:post_id>/share"' in api
    share_block = api.split('"/api/mobile/v1/kids/posts/<int:post_id>/share"', 1)[1].split('@bp.route', 1)[0]
    assert "post_visible_to" in share_block
    assert "like_count" in share_block or "likes" in share_block


def test_contacts_gates_on_messaging_feature():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/contacts"' in api
    block = api.split('"/api/mobile/v1/kids/contacts"', 1)[1].split('@bp.route', 1)[0]
    assert "messaging" in block


def test_block_user_removes_followers_and_prevents_self_block():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/block/<int:target_id>"' in api
    block = api.split('"/api/mobile/v1/kids/block/<int:target_id>"', 1)[1].split('@bp.route', 1)[0]
    assert "blocked_users" in block
    assert "DELETE FROM followers" in block
    assert "self_block" in block


def test_report_user_uses_correct_schema_columns():
    api = text("mobile/api.py")
    assert '"/api/mobile/v1/kids/report/user"' in api
    block = api.split('"/api/mobile/v1/kids/report/user"', 1)[1].split('@bp.route', 1)[0]
    assert "reporter_id" in block
    assert "'USER'" in block
    assert "self_report" in block


def test_parent_time_limit_get_returns_current_limit_and_usage():
    api = text("mobile/api.py")
    # Route must exist with GET method
    assert '"/api/mobile/v1/parent/time-limit/<int:child_id>"' in api
    assert '"GET"' in api
    # Handler must query child_time_limits and minutes_today
    assert "child_time_limits" in api
    assert "minutes_today" in api
    assert "minutes_used_today" in api


def test_all_existing_phase2_routes_still_present():
    api = text("mobile/api.py")
    core_routes = [
        "/api/mobile/v1/kids/home",
        "/api/mobile/v1/kids/chat/<int:peer_id>",
        "/api/mobile/v1/kids/posts/<int:post_id>/comment",
        "/api/mobile/v1/kids/posts/<int:post_id>/like",
        "/api/mobile/v1/parent/controls/<int:child_id>",
        "/api/mobile/v1/admin/reviews",
        "/api/mobile/v1/admin/dashboard",
    ]
    for route in core_routes:
        assert route in api, f"Existing route was lost: {route}"


def test_screen_matrix_has_17_partial_baseline():
    matrix = text("LITTLENET_SCREEN_MATRIX.md")
    assert "PARTIAL: 17" in matrix

