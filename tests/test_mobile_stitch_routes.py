from pathlib import Path

from app import app


def test_canonical_flutter_social_routes_are_registered():
    routes = {rule.rule: set(rule.methods or ()) for rule in app.url_map.iter_rules()}

    required = {
        '/api/mobile/v1/kids/posts/<int:post_id>',
        '/api/mobile/v1/kids/friends',
        '/api/mobile/v1/kids/chat/<int:peer_id>/share',
        '/api/mobile/v1/kids/saved',
        '/api/mobile/v1/kids/profiles/<int:target_id>',
        '/api/mobile/v1/kids/profiles/<int:target_id>/actions',
        '/api/mobile/v1/kids/reports',
        '/api/mobile/v1/kids/safety',
    }

    assert required <= routes.keys()
    assert 'POST' in routes['/api/mobile/v1/kids/chat/<int:peer_id>/share']
    assert {'GET', 'POST'} <= routes['/api/mobile/v1/kids/reports']
    assert 'POST' in routes['/api/mobile/v1/kids/profiles/<int:target_id>/actions']


def test_reported_user_moderation_has_preview_enforcement_and_migrated_escalation():
    source = Path('mobile/admin_api.py').read_text(encoding='utf-8')
    migration = Path('db/migrations/20260908093000_native_admin_escalation.sql').read_text(encoding='utf-8')

    assert "ctype == 'USER'" in source
    assert "account_status='SUSPENDED'" in source

    escalation = source.split("if requested == 'ESCALATE':", 1)[1].split("db_status =", 1)[0]
    assert 'INSERT INTO moderation_reviews' in escalation
    # ESCALATE should leave the locked moderation event open by not issuing a
    # database UPDATE that rewrites its status. Returning status='OPEN' in the
    # JSON response is expected and must not be mistaken for a DB mutation.
    assert "UPDATE moderation_events SET status='OPEN'" not in escalation
    assert "status='OPEN'" in source  # event lock requires an open review

    assert 'DROP CONSTRAINT IF EXISTS moderation_reviews_event_id_key' in migration
    assert "CHECK (action IN ('APPROVE','BLOCK','ESCALATE'))" in migration
