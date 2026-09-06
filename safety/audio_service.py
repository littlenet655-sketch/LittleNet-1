"""Retired LittleNet audio compatibility shim.

Standalone audio, voice upload, story music and Whisper transcription are not
part of the locked product scope. This module remains only so legacy imports or
historic database rows fail closed instead of crashing an older deployment.
No audio model is loaded and no audio content can be approved here.
"""


def check_audio(_path):
    return {
        'adult_score': 0.0,
        'sexual_score': 0.0,
        'violence_score': 0.0,
        'weapon_score': 0.0,
        'toxicity_score': 0.0,
        'general_score': 1.0,
        'category': 'AUDIO_RETIRED',
        'total_safety_failure': True,
        'partial_safety_failure': False,
        'errors': ['standalone_audio_disabled', 'remote_ai_unavailable'],
    }


def moderate_audio_safely(*_args, **_kwargs):
    from .policy import Decision
    signals = check_audio(None)
    return signals, Decision('BLOCK', 100.0, 'Standalone audio and voice uploads are disabled in LittleNet')
