"""Shared safety helpers.

All adapters remain optional/lazy. A feature flag that is disabled is not a
failure; a feature flag that is enabled but cannot run becomes a partial safety
failure so policy.py can fail closed to REVIEW/BLOCK.
"""
from __future__ import annotations
import os
import queue
import threading
from typing import Any, Callable

BASE_SIGNAL_KEYS=(
    'adult_score','sexual_score','violence_score','weapon_score','toxicity_score',
    'general_score','category','total_safety_failure','partial_safety_failure','errors'
)

class ModelTimeout(RuntimeError):
    pass

def env_flag(name:str, default:bool=False)->bool:
    raw=os.getenv(name,'1' if default else '0').strip().lower()
    return raw in {'1','true','yes','on','enabled'}

def timeout_seconds(name:str, default:float)->float:
    specific=os.getenv(f'LITTLENET_{name.upper()}_TIMEOUT_SECONDS','').strip()
    general=os.getenv('LITTLENET_MODEL_TIMEOUT_SECONDS','').strip()
    raw=specific or general or str(default)
    try:return max(1.0,float(raw))
    except ValueError:return default

def timed_call(name:str, fn:Callable[[],Any], seconds:float|None=None)->Any:
    """Best-effort request timeout using a daemon worker.

    The caller can return fail-closed immediately if an inference call stalls.
    Modal/Gunicorn request timeouts remain the outer hard-stop for the process.
    """
    q:queue.Queue=queue.Queue(maxsize=1)
    def run():
        try:q.put((True,fn()))
        except BaseException as exc:q.put((False,exc))
    t=threading.Thread(target=run,name=f'littlenet-{name}',daemon=True);t.start()
    try:ok,value=q.get(timeout=seconds or timeout_seconds(name,90))
    except queue.Empty as exc:raise ModelTimeout(f'{name}_timeout') from exc
    if ok:return value
    raise value

def normalize_signals(signals:dict|None, *, category:str='UNKNOWN')->dict:
    raw=dict(signals or {})
    errors=raw.get('errors') or []
    if isinstance(errors,str):errors=[errors]
    out={
        'adult_score':float(raw.get('adult_score',0) or 0),
        'sexual_score':float(raw.get('sexual_score',raw.get('adult_score',0)) or 0),
        'violence_score':float(raw.get('violence_score',0) or 0),
        'weapon_score':float(raw.get('weapon_score',0) or 0),
        'toxicity_score':float(raw.get('toxicity_score',0) or 0),
        'general_score':float(raw.get('general_score',0) or 0),
        'category':str(raw.get('category') or category).upper(),
        'total_safety_failure':bool(raw.get('total_safety_failure',False)),
        'partial_safety_failure':bool(raw.get('partial_safety_failure',False)),
        'errors':list(dict.fromkeys(str(x) for x in errors if x)),
    }
    # Preserve non-contract diagnostic keys such as transcript/model scores.
    for k,v in raw.items():
        if k not in out:out[k]=v
    out['adult_score']=max(out['adult_score'],out['sexual_score'])
    out['general_score']=max(out['general_score'],out['adult_score'],out['violence_score'],out['weapon_score'],out['toxicity_score'])
    return out
