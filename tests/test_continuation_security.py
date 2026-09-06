from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def text(path):
    return (ROOT / path).read_text(encoding='utf-8')


def test_parent_registration_is_intercepted_by_email_otp_gate():
    api = text('auth/api.py')
    otp = text('auth/parent_email_otp.py')
    assert "request.path.rstrip('/')!='/register-parent'" in api
    assert "'PARENT',%s,'PENDING_APPROVAL'" in otp
    assert "UPDATE users SET account_status='ACTIVE'" in otp
    assert 'OTP_MAX_ATTEMPTS = 5' in otp
    assert "INTERVAL '10 minutes'" in otp
    assert 'code_hash' in otp


def test_parent_otp_routes_require_pending_registration_session():
    api = text('auth/api.py')
    assert "session.get('pending_parent_user_id')" in api
    assert "session.get('pending_parent_email')" in api
    assert api.count('@login_required') >= 2


def test_parent_otp_never_persists_plaintext_code():
    otp = text('auth/parent_email_otp.py')
    assert 'hashlib.sha256' in otp
    assert 'hmac.compare_digest' in otp
    assert 'code VARCHAR' not in otp
    assert 'code TEXT' not in otp


def test_parent_liveness_has_no_demo_or_manual_capture_bypass():
    page = text('auth/templates/parent_verify.html')
    assert 'Demo Liveness' not in page
    assert 'drawFallbackSelfie' not in page
    assert 'manualCaptureBtn' not in page
    assert 'blinkVerified' in page
    assert 'navigator.mediaDevices.getUserMedia' in page
    assert 'No verification bypass is available' in page


def test_server_face_path_remains_anti_spoof_fail_closed():
    face = text('safety/face_service.py')
    assert 'anti_spoofing=True' in face
    assert "reason': 'liveness_failed'" in face
    assert "reason': 'liveness_unavailable'" in face


def test_guardian_adult_face_uses_split_ai_worker_when_configured():
    face = text('safety/face_service.py')
    client = text('safety/remote_client.py')
    server = text('ai_server.py')
    assert 'face_adult_verify' in face
    assert 'def face_adult_verify' in client
    assert '/ai/face/adult' in client
    assert '@app.post("/ai/face/adult")' in server
    assert 'adult_face_service_unavailable' in face


def test_whisper_is_restored_to_audio_pipeline_and_modal_runtime():
    audio = text('safety/audio_service.py')
    modal = text('modal_ai.py')
    requirements = text('requirements-ai.txt')
    assert 'import whisper' in audio
    assert 'whisper.load_model' in audio
    assert "timeout_seconds('whisper', 180)" in audio
    assert '_signals_from_transcript' in audio
    assert 'scan_pii(transcript)' in audio
    assert "pii.get('categories')" in audio
    assert 'openai-whisper>=20250625' in requirements
    assert 'openai-whisper>=20250625' in modal
    assert 'whisper_base' in modal


def test_audio_transcription_failure_still_fails_closed():
    audio = text('safety/audio_service.py')
    assert "'partial_safety_failure': True" in audio
    assert 'audio_transcription_unavailable' in audio
    assert 'remote_ai_unavailable' in audio
