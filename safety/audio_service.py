import os
from .common import normalize_signals,timed_call,timeout_seconds
from .text_service import check_text
_MODEL=None

def _transcribe_impl(path):
    global _MODEL
    from faster_whisper import WhisperModel
    if _MODEL is None:
        requested=os.getenv('LITTLENET_DEVICE','auto').lower();device='cpu'
        if requested!='cpu':
            try:
                import ctranslate2
                if ctranslate2.get_cuda_device_count()>0:device='cuda'
            except Exception:pass
        model_name=os.getenv('LITTLENET_WHISPER_MODEL','tiny').strip() or 'tiny'
        _MODEL=WhisperModel(model_name,device=device,compute_type='float16' if device=='cuda' else 'int8')
    segments,_=_MODEL.transcribe(path,beam_size=1,vad_filter=True)
    return ' '.join(s.text.strip() for s in segments).strip()

def transcribe(path):
    try:return timed_call('whisper',lambda:_transcribe_impl(path),timeout_seconds('whisper',150))
    except Exception as exc:raise RuntimeError(f'whisper_unavailable:{exc}')

def check_audio(path):
    from .remote_client import enabled, moderate_file
    if enabled():
        try:return normalize_signals(moderate_file('AUDIO',path),category='AUDIO')
        except Exception:return normalize_signals({'category':'AUDIO','total_safety_failure':True,'errors':['remote_ai_unavailable'],'transcript':''},category='AUDIO')
    try:
        text=transcribe(path);out=check_text(text);out['transcript']=text;out['category']=out['category'] if out['category']!='TEXT' else 'AUDIO'
        return normalize_signals(out,category='AUDIO')
    except Exception as exc:
        return normalize_signals({'category':'AUDIO','total_safety_failure':True,'errors':['whisper_timeout' if 'timeout' in str(exc) else 'whisper'],'transcript':''},category='AUDIO')
