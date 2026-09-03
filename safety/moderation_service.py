import json
from database.connection import execute, fetch_one
from .common import normalize_signals
from .policy import decide
from .text_service import check_text
from .audio_service import check_audio
from .visual_service import check_image, check_video

def safety_level(child_id):
    row=fetch_one('SELECT safety_level FROM parent_safety_settings WHERE child_id=%s',(child_id,));return (row or {}).get('safety_level','STRICT')

def evaluate(child_id,content_type,payload,adult_threshold=.40):
    t=content_type.upper();signals=check_text(payload) if t=='TEXT' else check_audio(payload) if t in {'AUDIO','VOICE'} else check_video(payload) if t=='VIDEO' else check_image(payload)
    signals=normalize_signals(signals,category=t);d=decide(signals,safety_level(child_id),adult_threshold);return signals,d

def record(child_id,content_type,content_id,signals,decision):
    signals=normalize_signals(signals,category=content_type);status='OPEN' if decision.action=='REVIEW' else 'RESOLVED'
    return execute('''INSERT INTO moderation_events(child_id,content_type,content_id,risk_score,adult_score,violence_score,weapon_score,toxicity_score,decision,reason,signals,status) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s::jsonb,%s) RETURNING event_id''',(
        child_id,content_type,content_id,decision.risk,float(signals.get('adult_score',0))*100,float(signals.get('violence_score',0))*100,float(signals.get('weapon_score',0))*100,float(signals.get('toxicity_score',0))*100,decision.action,decision.reason,json.dumps(signals),status),returning=True)['event_id']
