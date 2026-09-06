import os

from .common import normalize_signals, timed_call, timeout_seconds

_WHISPER = None
_WHISPER_MODEL_NAME = None


def _transcribe_local(path):
    """Transcribe speech with OpenAI Whisper, loaded lazily and cached per worker."""
    global _WHISPER, _WHISPER_MODEL_NAME
    import whisper

    model_name = (os.environ.get('LITTLENET_WHISPER_MODEL') or 'base').strip() or 'base'
    if _WHISPER is None or _WHISPER_MODEL_NAME != model_name:
        cache_dir = os.environ.get('LITTLENET_MODEL_CACHE') or os.environ.get('XDG_CACHE_HOME')
        kwargs = {'name': model_name}
        if cache_dir:
            kwargs['download_root'] = os.path.join(cache_dir, 'whisper')
        _WHISPER = whisper.load_model(**kwargs)
        _WHISPER_MODEL_NAME = model_name

    result = _WHISPER.transcribe(path, fp16=_whisper_cuda_available())
    if not isinstance(result, dict):
        return ''
    return str(result.get('text') or '').strip()


def _whisper_cuda_available():
    try:
        import torch
        return bool(torch.cuda.is_available())
    except Exception:
        return False


def _signals_from_transcript(transcript):
    """Apply the normal text and PII safety pipeline to transcribed speech."""
    from .text_service import check_text
    from safety.pii_service import scan_pii

    sig = dict(check_text(transcript))
    sig['category'] = 'AUDIO'
    sig['transcript'] = transcript
    sig['transcription_model'] = f"whisper:{_WHISPER_MODEL_NAME or 'base'}"

    pii = scan_pii(transcript)
    if pii.get('detected') and pii.get('policy_action') == 'BLOCK':
        sig['general_score'] = max(float(sig.get('general_score', 0) or 0), 1.0)
        sig['category'] = 'AUDIO_PII'
        sig['pii_detected'] = True
        sig['pii_types'] = pii.get('types') or pii.get('matches') or []
    return normalize_signals(sig, category='AUDIO')


def check_audio(path):
    """Transcribe audio and apply the same safety policy used for text.

    The lightweight web app delegates to the configured heavy AI service. On the
    AI worker itself, Whisper runs locally. Any missing/failed transcription fails
    closed to parent review instead of treating unanalyzed speech as safe.
    """
    audio_req = os.environ.get('AUDIO_MODERATION_REQUIRED', 'true').lower() in ('true', '1', 'yes')
    from .remote_client import enabled, moderate_file

    if enabled():
        try:
            remote_sig = moderate_file('AUDIO', path)
            transcript = str(remote_sig.get('transcript') or '').strip()
            if audio_req and not transcript:
                remote_sig['partial_safety_failure'] = True
                remote_sig['requires_human_review'] = True
                remote_sig['errors'] = list(remote_sig.get('errors') or []) + ['audio_transcription_unavailable']
                remote_sig['transcript'] = '[Audio transcription unavailable - routed to safety review]'
            return normalize_signals(remote_sig, category='AUDIO')
        except Exception:
            return normalize_signals(
                {'category': 'AUDIO', 'total_safety_failure': True, 'errors': ['remote_ai_unavailable'], 'transcript': ''},
                category='AUDIO',
            )

    try:
        transcript = timed_call(
            'whisper',
            lambda: _transcribe_local(path),
            timeout_seconds('whisper', 180),
        )
        if transcript:
            return _signals_from_transcript(transcript)
        if audio_req:
            return normalize_signals(
                {
                    'adult_score': 0.0,
                    'sexual_score': 0.0,
                    'toxicity_score': 0.0,
                    'general_score': 0.20,
                    'partial_safety_failure': True,
                    'requires_human_review': True,
                    'errors': ['audio_transcription_empty'],
                    'transcript': '[No intelligible speech detected - routed to safety review]',
                    'category': 'AUDIO',
                },
                category='AUDIO',
            )
    except Exception as exc:
        if audio_req:
            err = 'whisper_timeout' if 'timeout' in str(exc).lower() else 'whisper_unavailable'
            return normalize_signals(
                {
                    'adult_score': 0.0,
                    'sexual_score': 0.0,
                    'toxicity_score': 0.0,
                    'general_score': 0.20,
                    'partial_safety_failure': True,
                    'requires_human_review': True,
                    'errors': [err, 'audio_transcription_unavailable'],
                    'transcript': '[Audio transcription unavailable - routed to safety review]',
                    'category': 'AUDIO',
                },
                category='AUDIO',
            )

    return normalize_signals(
        {
            'adult_score': 0.0,
            'sexual_score': 0.0,
            'toxicity_score': 0.0,
            'general_score': 0.0,
            'transcript': '[Audio moderation disabled]',
            'category': 'AUDIO',
        },
        category='AUDIO',
    )


def moderate_audio_safely(child_id: int, audio_path: str, duration_sec: float = 0.0, simulated_transcript: str = ""):
    """Evaluate transcribed audio using PII, text moderation, and fail-closed policy."""
    from safety.pii_service import scan_pii
    from .policy import decide, Decision
    from .text_service import check_text

    if simulated_transcript and simulated_transcript.strip():
        pii = scan_pii(simulated_transcript)
        if pii['detected'] and pii['policy_action'] == 'BLOCK':
            text_sig = {
                'adult_score': 0.0, 'sexual_score': 0.0, 'toxicity_score': 0.0,
                'violence_score': 0.0, 'weapon_score': 0.0, 'general_score': 1.0,
                'category': 'AUDIO', 'transcript': simulated_transcript, 'errors': []
            }
            return text_sig, Decision('BLOCK', 100.0, 'Personal contact or phone number sharing in audio transcript')

        text_sig = check_text(simulated_transcript)
        text_sig['category'] = 'AUDIO'
        text_sig['transcript'] = simulated_transcript
        text_sig['partial_safety_failure'] = False
        decision = decide(text_sig)
        return text_sig, decision

    sig = check_audio(audio_path)
    decision = decide(sig)
    return sig, decision
