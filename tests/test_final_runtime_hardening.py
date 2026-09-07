from pathlib import Path

import pytest
from flask import Flask, session

import services.media_outbox as media_outbox
import services.media_persistence as media_persistence
import services.object_storage as object_storage


ROOT = Path(__file__).resolve().parents[1]


def _text(path):
    return (ROOT / path).read_text(encoding="utf-8")


def _configure_r2(monkeypatch):
    monkeypatch.setenv("R2_ACCOUNT_ID", "acct-test")
    monkeypatch.setenv("R2_ACCESS_KEY_ID", "key")
    monkeypatch.setenv("R2_SECRET_ACCESS_KEY", "secret")
    monkeypatch.setenv("R2_BUCKET", "private-media")


def test_persist_before_db_uploads_first_and_removes_ephemeral_file(tmp_path, monkeypatch):
    local = tmp_path / "photo.jpg"
    local.write_bytes(b"moderated-image")
    calls = []

    monkeypatch.setattr(media_persistence, "enabled", lambda: True)

    def fake_upload(path, key):
        calls.append((path, key))
        assert Path(path).exists()
        return "uploads/r2/posts/7/private-photo.jpg"

    monkeypatch.setattr(media_persistence, "upload_file", fake_upload)
    ref = media_persistence.persist_before_db(str(local), "posts", 7)

    assert ref == "uploads/r2/posts/7/private-photo.jpg"
    assert len(calls) == 1
    assert not local.exists()


def test_persist_before_db_fails_closed_without_r2(tmp_path, monkeypatch):
    local = tmp_path / "photo.jpg"
    local.write_bytes(b"moderated-image")
    monkeypatch.setattr(media_persistence, "enabled", lambda: False)

    with pytest.raises(RuntimeError, match="R2 is required"):
        media_persistence.persist_before_db(str(local), "posts", 7)

    assert local.exists()


def test_failed_r2_compensation_is_queued_for_durable_retry(monkeypatch):
    queued = []

    def broken_delete(reference):
        raise RuntimeError("temporary R2 outage")

    monkeypatch.setattr(media_persistence, "delete_reference", broken_delete)
    monkeypatch.setattr(
        media_outbox,
        "enqueue_delete",
        lambda reference, source_table="compensation", source_id=None: queued.append(
            (reference, source_table, source_id)
        ),
    )

    media_persistence.rollback_reference("uploads/r2/posts/7/orphan.jpg")
    assert queued == [("uploads/r2/posts/7/orphan.jpg", "compensation", None)]


def test_r2_delete_never_reports_success_when_storage_is_unconfigured(monkeypatch):
    for name in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET"):
        monkeypatch.delenv(name, raising=False)

    with pytest.raises(RuntimeError, match="R2 is not configured"):
        object_storage.delete_reference("uploads/r2/posts/7/private.jpg")


def test_outbox_retains_retry_state_when_private_delete_fails(monkeypatch):
    writes = []
    monkeypatch.setattr(
        media_outbox,
        "fetch_all",
        lambda sql, params=(): [{"outbox_id": 11, "reference": "uploads/r2/x.jpg"}],
    )
    monkeypatch.setattr(media_outbox, "execute", lambda sql, params=(): writes.append((sql, params)))
    monkeypatch.setattr(
        object_storage,
        "delete_reference",
        lambda reference: (_ for _ in ()).throw(RuntimeError("R2 unavailable")),
    )

    result = media_outbox.reconcile_pending_deletes()
    assert result == {"checked": 1, "completed": 0, "failed": 1}
    assert any("attempts=attempts+1" in sql and "last_error=%s" in sql for sql, _ in writes)
    assert not any("completed_at=COALESCE" in sql for sql, _ in writes)


def test_signed_r2_url_fails_closed_when_child_surface_is_locked(monkeypatch):
    _configure_r2(monkeypatch)
    app = Flask(__name__)
    app.secret_key = "test-secret"

    class FakeClient:
        def generate_presigned_url(self, *args, **kwargs):
            raise AssertionError("R2 URL must not be signed for a locked child")

    monkeypatch.setattr(object_storage, "_client", lambda: FakeClient())
    import services.social as social

    monkeypatch.setattr(social, "child_surface_open", lambda uid, feature=None: False)
    with app.test_request_context("/uploads/r2/posts/7/x.jpg"):
        session["user_id"] = 7
        session["role"] = "CHILD"
        with pytest.raises(PermissionError, match="child_media_locked"):
            object_storage.signed_download_url("uploads/r2/posts/7/x.jpg")


def test_post_and_message_media_are_persisted_before_database_insert():
    posts = _text("uploadPost/routes.py")
    messages = _text("childMessage/routes.py")

    post_persist = posts.index("persist_before_db(path,namespace,session['user_id'])")
    post_insert = posts.index("INSERT INTO posts", post_persist)
    assert post_persist < post_insert

    message_persist = messages.index("persist_before_db(path,'messages',session['user_id'])")
    message_insert = messages.index("INSERT INTO child_messages", message_persist)
    assert message_persist < message_insert


def test_database_migration_has_identity_relationship_and_delete_outbox_invariants():
    migration = _text("db/migrations/20260907150000_final_runtime_invariants.sql")
    for token in (
        "users_username_ci_unique",
        "users_email_ci_unique",
        "media_delete_outbox",
        "trg_posts_media_delete_outbox",
        "trg_messages_media_delete_outbox",
        "trg_validate_message_conversation",
        "trg_validate_parent_child_roles",
        "trg_validate_parent_control_roles",
        "trg_validate_parent_safety_roles",
    ):
        assert token in migration


def test_parent_mode_uses_full_document_navigation_for_page_specific_scripts():
    parent = _text("parent/templates/parent_base.html")
    assert 'data-no-instant' in parent
    assert parent.count('data-no-instant') >= 10


def test_retired_audio_is_absent_from_android_runtime_surface():
    manifest = _text("android/app/src/main/AndroidManifest.xml")
    activity = _text("android/app/src/main/java/com/littlenet/app/MainActivity.java")
    assert "android.permission.RECORD_AUDIO" not in manifest
    assert "RECORD_SOUND_ACTION" not in activity
    assert "RESOURCE_AUDIO_CAPTURE" not in activity
    assert "pendingWebPermission" in activity
    assert "onRequestPermissionsResult" in activity
    assert "MIXED_CONTENT_NEVER_ALLOW" in activity


def test_stale_kivy_ngrok_entrypoint_is_removed():
    assert not (ROOT / "main.py").exists()
