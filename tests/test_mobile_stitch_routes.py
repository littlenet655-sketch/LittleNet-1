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


def test_reported_user_moderation_has_preview_enforcement_and_safe_escalation():
    source = Path('mobile/admin_api.py').read_text(encoding='utf-8')
    assert "ctype == 'USER'" in source
    assert "account_status='SUSPENDED'" in source
    assert "'MODERATION_ESCALATED'" in source
    # The schema permits only APPROVE/BLOCK in moderation_reviews. ESCALATE
    # therefore belongs in the audit log and must not consume the event's
    # single final-review row.
    escalation = source.split("if requested == 'ESCALATE':", 1)[1].split("db_status =", 1)[0]
    assert 'INSERT INTO moderation_reviews' not in escalation
