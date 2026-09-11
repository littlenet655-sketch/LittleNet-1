from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_kids_native_surface_and_mobile_api_cover_locked_scope():
    kids = text("mobile_flutter/lib/screens/kids.dart")
    feed = text("mobile_flutter/lib/screens/kids_feed.dart")
    learning = text("mobile_flutter/lib/screens/kids_learning.dart")
    onboarding = text("mobile_flutter/lib/screens/kids_onboarding.dart")
    api = text("mobile/api.py")

    flutter_tokens = [
        "KidsHomePage", "DiscoverPage", "CreatePostPage", "ReelsPage",
        "MessagesPage", "ChatPage", "ProfilePage", "StoryViewer",
        "NotificationsScreen", "LearningScreen", "QuizGateScreen",
        "ImageSource.camera", "ImageSource.gallery",
    ]
    all_flutter = "\n".join((kids, feed, learning, onboarding))
    for token in flutter_tokens:
        assert token in all_flutter, token

    routes = [
        "/api/mobile/v1/kids/home",
        "/api/mobile/v1/kids/reels",
        "/api/mobile/v1/kids/discover",
        "/api/mobile/v1/kids/profile",
        "/api/mobile/v1/kids/notifications",
        "/api/mobile/v1/kids/messages",
        "/api/mobile/v1/kids/chat/<int:peer_id>",
        "/api/mobile/v1/kids/follow/<int:child_id>",
        "/api/mobile/v1/kids/posts/<int:post_id>/like",
        "/api/mobile/v1/kids/posts/<int:post_id>/save",
        "/api/mobile/v1/kids/posts/<int:post_id>/comment",
        "/api/mobile/v1/kids/posts",
        "/api/mobile/v1/kids/learning",
        "/api/mobile/v1/kids/quiz",
        "/api/mobile/v1/kids/feed-view/<int:post_id>",
        "/api/mobile/v1/kids/face/enroll",
    ]
    for route in routes:
        assert route in api, route

    # Safety and parent-owned gates must remain server-side rather than only UI.
    for token in (
        "face_enrollment_required", "onboarding_quiz_required",
        "disabled_by_parent", "quiet_hours", "screen_time_limit",
        "quiz_required", "approved_connection_required",
        "scan_pii", "evaluate(uid", "persist_before_db",
    ):
        assert token in api, token


def test_parent_native_surface_and_mobile_api_cover_locked_scope():
    auth = text("mobile_flutter/lib/screens/auth.dart")
    parent = text("mobile_flutter/lib/screens/parent.dart")
    api = text("mobile/api.py")
    all_flutter = auth + "\n" + parent

    for token in (
        "ParentRegistrationScreen", "ParentVerificationScreen", "ParentShell",
        "ParentDashboard", "ParentSafety", "ParentChildren", "ParentActivity",
        "ChildControlsScreen", "ScreenTimeScreen", "showDatePicker",
        "Open camera & verify", "Approve", "Block",
    ):
        assert token in all_flutter, token

    for route in (
        "/api/mobile/v1/auth/parent/register",
        "/api/mobile/v1/auth/parent/verify-email",
        "/api/mobile/v1/auth/parent/resend-email",
        "/api/mobile/v1/auth/parent/verify-liveness",
        "/api/mobile/v1/parent/dashboard",
        "/api/mobile/v1/parent/children",
        "/api/mobile/v1/parent/children/<int:child_id>/face/enroll",
        "/api/mobile/v1/parent/controls/<int:child_id>",
        "/api/mobile/v1/parent/time-limit/<int:child_id>",
        "/api/mobile/v1/parent/safety",
        "/api/mobile/v1/parent/safety/<int:event_id>",
        "/api/mobile/v1/parent/follow-requests",
        "/api/mobile/v1/parent/follow-requests/action",
        "/api/mobile/v1/parent/notifications",
    ):
        assert route in api, route

    for token in ("verify_parent_email_otp", "verify_adult_face", "owns(pid, child_id)"):
        assert token in api, token


def test_admin_native_surface_api_and_database_support_three_actions():
    admin = text("mobile_flutter/lib/screens/admin.dart")
    api = text("mobile/admin_api.py")
    migration = text("db/migrations/20260908093000_native_admin_escalation.sql")

    for token in ("AdminShell", "APPROVE", "BLOCK", "ESCALATE", "users", "audit"):
        assert token in admin.upper() if token.isupper() else token in admin, token

    for route in (
        "/api/mobile/v1/admin/reviews/<int:event_id>",
        "/api/mobile/v1/admin/users",
        "/api/mobile/v1/admin/audit",
    ):
        assert route in api, route
    assert "requested not in {'APPROVE', 'BLOCK', 'ESCALATE'}" in api

    assert "DROP CONSTRAINT IF EXISTS moderation_reviews_event_id_key" in migration
    assert "'APPROVE','BLOCK','ESCALATE'" in migration
    assert "idx_moderation_reviews_event" in migration


def test_native_auth_and_release_contracts_are_end_to_end_not_webview():
    auth = text("mobile_flutter/lib/screens/auth.dart")
    api = text("mobile/api.py")
    pubspec = text("mobile_flutter/pubspec.yaml")
    prepare = text("mobile_flutter/tool/prepare_android.sh")

    assert "webview_flutter" not in pubspec.lower()
    assert "flutter_secure_storage" in pubspec
    assert "image_picker" in pubspec
    assert "android:usesCleartextTraffic=\"false\"" in prepare
    assert "FlutterActivity" in prepare
    assert "preferredCameraDevice: CameraDevice.front" in auth
    assert "/api/mobile/v1/auth/login" in api
    assert "/api/mobile/v1/auth/face-login" in api
    assert "verify(user[\"user_id\"], path)" in api
