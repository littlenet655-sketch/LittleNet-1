import json
import os
from datetime import datetime, time
from zoneinfo import ZoneInfo
from database.connection import fetch_one, execute

SAFE_CATEGORIES = [
    'Other','Science','Math','Art','Sports','Music','Technology','Education',
    'Nature','Books','Coding','General Knowledge'
]
EDUCATIONAL_CATEGORIES = ['Science','Math','Technology','Education','Nature','Books','Coding','General Knowledge']
FEATURE_COLUMNS = {
    'reels':'allow_reels',
    'stories':'allow_stories',
    'messaging':'allow_messaging',
    'posting':'allow_posting',
    'discover':'allow_discover',
}


def _clock(value, fallback):
    if isinstance(value, time):
        return value.strftime('%H:%M')
    if value is None:
        return fallback
    text=str(value).strip()
    return text[:5] if len(text)>=5 else fallback


def _defaults(child_id=None):
    return {
        'child_id':child_id,
        'allow_reels':True,
        'allow_stories':True,
        'allow_messaging':True,
        'allow_posting':True,
        'allow_discover':True,
        'quiet_hours_enabled':False,
        'quiet_start':'21:00',
        'quiet_end':'07:00',
        'educational_only_feed':False,
        'allowed_categories':list(SAFE_CATEGORIES),
    }


def controls_for_child(child_id):
    row=fetch_one('SELECT * FROM parent_control_settings WHERE child_id=%s',(child_id,))
    if not row:return _defaults(child_id)
    out=_defaults(child_id);out.update(dict(row))
    cats=out.get('allowed_categories') or list(SAFE_CATEGORIES)
    out['allowed_categories']=[c for c in cats if c in SAFE_CATEGORIES] or list(SAFE_CATEGORIES)
    out['quiet_start']=_clock(out.get('quiet_start'),'21:00')
    out['quiet_end']=_clock(out.get('quiet_end'),'07:00')
    return out


def feature_allowed(child_id,feature):
    col=FEATURE_COLUMNS.get(feature)
    if not col:return True
    return bool(controls_for_child(child_id).get(col,True))


def effective_categories(child_id):
    c=controls_for_child(child_id)
    allowed=[x for x in c['allowed_categories'] if x in SAFE_CATEGORIES]
    if c.get('educational_only_feed'):
        allowed=[x for x in allowed if x in EDUCATIONAL_CATEGORIES]
    return allowed or (EDUCATIONAL_CATEGORIES if c.get('educational_only_feed') else list(SAFE_CATEGORIES))


def _parse_clock(value):
    try:
        parts=str(value).split(':')
        if len(parts)<2:raise ValueError
        hour,minute=int(parts[0]),int(parts[1])
        if not (0<=hour<=23 and 0<=minute<=59):raise ValueError
        return time(hour,minute)
    except (TypeError,ValueError):
        raise ValueError('invalid_quiet_hours')


def quiet_hours_state(child_id, at=None):
    controls=controls_for_child(child_id)
    if not controls.get('quiet_hours_enabled'):
        return {'active':False,'start':controls['quiet_start'],'end':controls['quiet_end']}
    if at is None:
        try:tz=ZoneInfo(os.getenv('APP_TIMEZONE','Asia/Kolkata'))
        except Exception:tz=ZoneInfo('UTC')
        at=datetime.now(tz)
    current=at.timetz().replace(tzinfo=None) if getattr(at,'tzinfo',None) else at.time()
    try:
        start=_parse_clock(controls['quiet_start']);end=_parse_clock(controls['quiet_end'])
    except ValueError:
        start=time(21,0);end=time(7,0)
    if start==end:
        active=True  # explicit equal times means all-day quiet mode
    elif start<end:
        active=start<=current<end
    else:
        active=current>=start or current<end
    return {'active':active,'start':controls['quiet_start'],'end':controls['quiet_end']}


def quiet_hours_active(child_id, at=None):
    return bool(quiet_hours_state(child_id,at)['active'])


def save_controls(parent_id,child_id,form):
    allowed=[x for x in form.getlist('allowed_categories') if x in SAFE_CATEGORIES]
    if not allowed: allowed=list(SAFE_CATEGORIES)
    qstart=_clock(form.get('quiet_start'),'21:00');qend=_clock(form.get('quiet_end'),'07:00')
    # Reject malformed time strings before PostgreSQL sees them.
    _parse_clock(qstart);_parse_clock(qend)
    values={
        'allow_reels':'allow_reels' in form,
        'allow_stories':'allow_stories' in form,
        'allow_messaging':'allow_messaging' in form,
        'allow_posting':'allow_posting' in form,
        'allow_discover':'allow_discover' in form,
        'quiet_hours_enabled':'quiet_hours_enabled' in form,
        'educational_only_feed':'educational_only_feed' in form,
    }
    execute('''INSERT INTO parent_control_settings(
        child_id,parent_id,allow_reels,allow_stories,allow_messaging,allow_posting,allow_discover,
        quiet_hours_enabled,quiet_start,quiet_end,educational_only_feed,allowed_categories,updated_at
      ) VALUES(%s,%s,%s,%s,%s,%s,%s,%s,%s::time,%s::time,%s,%s::jsonb,NOW())
      ON CONFLICT(child_id) DO UPDATE SET parent_id=EXCLUDED.parent_id,allow_reels=EXCLUDED.allow_reels,
      allow_stories=EXCLUDED.allow_stories,allow_messaging=EXCLUDED.allow_messaging,allow_posting=EXCLUDED.allow_posting,
      allow_discover=EXCLUDED.allow_discover,quiet_hours_enabled=EXCLUDED.quiet_hours_enabled,
      quiet_start=EXCLUDED.quiet_start,quiet_end=EXCLUDED.quiet_end,educational_only_feed=EXCLUDED.educational_only_feed,
      allowed_categories=EXCLUDED.allowed_categories,updated_at=NOW()''',(
        child_id,parent_id,values['allow_reels'],values['allow_stories'],values['allow_messaging'],values['allow_posting'],
        values['allow_discover'],values['quiet_hours_enabled'],qstart,qend,values['educational_only_feed'],json.dumps(allowed)))
    return controls_for_child(child_id)
