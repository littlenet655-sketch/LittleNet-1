import os
from .common import normalize_signals


def check_audio(path):
    """Audio moderation.

    Speech-to-text transcription was removed at the project owner's request.
    If real audio moderation is needed later, plug an alternative here.
    When AUDIO_MODERATION_REQUIRED=true, unanalyzed audio fails safe to parent review.
    """
    audio_req = os.environ.get('AUDIO_MODERATION_REQUIRED', 'true').lower() in ('true', '1', 'yes')
    from .remote_client import enabled, moderate_file
    if enabled():
        try:
            remote_sig = moderate_file('AUDIO', path)
            if audio_req and not remote_sig.get('transcript'):
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
    
    if audio_req:
        # Audio moderation is required: unanalyzed audio must fail safe to parent review
        return normalize_signals(
            {
                'adult_score': 0.0, 'sexual_score': 0.0, 'toxicity_score': 0.0, 'general_score': 0.20,
                'partial_safety_failure': True,
                'requires_human_review': True,
                'errors': ['audio_transcription_unavailable'],
                'transcript': '[Audio transcription unavailable locally - routed to safety review]',
                'category': 'AUDIO',
            },
            category='AUDIO',
        )
    return normalize_signals(
        {
            'adult_score': 0.0, 'sexual_score': 0.0, 'toxicity_score': 0.0, 'general_score': 0.0,
            'transcript': '[Audio content is not transcribed/analyzed locally]', 'category': 'AUDIO',
        },
        category='AUDIO',
    )


def moderate_audio_safely(child_id: int, audio_path: str, duration_sec: float = 0.0, simulated_transcript: str = ""):
    """
    Evaluates audio content.
    If a transcript is provided or produced, runs text and PII moderation on the transcript.
    If no transcript is available and AUDIO_MODERATION_REQUIRED is true, marks
    partial_safety_failure=True and routes to REVIEW.
    """
    from safety.pii_service import scan_pii
    from .policy import decide, Decision
    from .text_service import check_text

    if simulated_transcript and simulated_transcript.strip():
        # 1. Screen transcript for PII and contact sharing
        pii = scan_pii(simulated_transcript)
        if pii['detected'] and pii['policy_action'] == 'BLOCK':
            text_sig = {
                'adult_score': 0.0, 'sexual_score': 0.0, 'toxicity_score': 0.0,
                'violence_score': 0.0, 'weapon_score': 0.0, 'general_score': 1.0,
                'category': 'AUDIO', 'transcript': simulated_transcript, 'errors': []
            }
            return text_sig, Decision('BLOCK', 100.0, 'Personal contact or phone number sharing in audio transcript')

        # 2. Moderation check on transcript text
        text_sig = check_text(simulated_transcript)
        text_sig['category'] = 'AUDIO'
        text_sig['transcript'] = simulated_transcript
        text_sig['partial_safety_failure'] = False
        decision = decide(text_sig)
        return text_sig, decision

    # No transcript available
    sig = check_audio(audio_path)
    decision = decide(sig)
    return sig, decision

