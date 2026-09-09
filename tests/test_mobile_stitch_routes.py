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
