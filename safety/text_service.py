import os,re
from .common import env_flag,normalize_signals,timed_call,timeout_seconds

ADULT_TERMS={
    'porn','pornography','nude','nudes','sex video','xxx','send nudes','sexual photo',
    'explicit photo','onlyfans','sexting','send me a nude','take your clothes off',
    'show me your body','show your body','naked pic','naked photo','private parts'
}
PROFANE={'fuck','bitch','asshole'}
BULLYING_TERMS={
    'kill yourself','nobody likes you','you are ugly','you are stupid','you are useless',
    'loser','idiot','worthless','go die','hate you','shut up','no one wants you','everyone hates you'
}
SEVERE_ABUSE_TERMS={
    'i will kill you','i am going to kill you','i will hurt you','i will beat you',
    'you deserve to die','go kill yourself','hurt yourself','cut yourself','hang yourself',
    'i will find you','i know where you live','i will come to your house'
}
GROOMING_PATTERNS=(
    r"\bdon'?t tell (?:your )?(?:mom|mum|mother|dad|father|parents?)\b",
    r"\bkeep (?:this|it) (?:a )?secret\b",
    r"\bour little secret\b",
    r"\bmeet me (?:alone|privately|outside|after school)\b",
    r"\bcome alone\b",
    r"\bdelete (?:this|our) chat\b",
    r"\bsend (?:me )?(?:a )?(?:pic|photo|selfie) (?:in|without|of)\b",
    r"\bwhat are you wearing\b",
    r"\bwhere do you live\b",
    r"\bwhat(?:'s| is) your address\b",
    r"\bgive me your (?:phone|number|snap|instagram|telegram)\b",
    r"\badd me on (?:snap|snapchat|instagram|telegram|whatsapp)\b",
)

_DETOX=None;_HF_TEXT=None

def _detox_scores(text):
    global _DETOX
    try:
        import torch
        if hasattr(torch, 'serialization') and hasattr(torch.serialization, 'add_safe_globals'):
            _orig_load = torch.load
            def _safe_load(*args, **kwargs):
                if 'weights_only' not in kwargs:
                    kwargs['weights_only'] = False
                return _orig_load(*args, **kwargs)
            torch.load = _safe_load
    except Exception:
        pass
    from detoxify import Detoxify
    model_name=os.getenv('LITTLENET_DETOXIFY_MODEL','original').strip() or 'original'
    if _DETOX is None:
        try:_DETOX=Detoxify(model_name)
        except Exception:_DETOX=Detoxify('original')
    return _DETOX.predict(text) if text else {}

def _optional_hf_scores(text):
    if not env_flag('LITTLENET_ENABLE_TEXT_CLASSIFIER'):return None
    model_id=os.getenv('LITTLENET_TEXT_SAFETY_MODEL','').strip()
    if not model_id:raise RuntimeError('text_classifier_model_missing')
    global _HF_TEXT
    if _HF_TEXT is None:
        from transformers import pipeline
        _HF_TEXT=pipeline('text-classification',model=model_id,top_k=None,device=-1)
    rows=_HF_TEXT(text[:4000])
    if rows and isinstance(rows[0],list):rows=rows[0]
    harmful=0.0;details={}
    for row in rows or []:
        label=str(row.get('label','')).lower();score=float(row.get('score',0) or 0);details[label]=score
        if any(k in label for k in ('toxic','hate','bully','harass','self-harm','self_harm','unsafe')):harmful=max(harmful,score)
    return {'toxicity':harmful,'labels':details}

def check_text(text:str):
    from .remote_client import enabled, moderate_text
    text=(text or '').strip();low=text.lower()

    # Deterministic hard-safety evidence is computed locally first so a remote
    # classifier outage can never erase known grooming/18+/severe-abuse signals.
    adult=1.0 if any(t in low for t in ADULT_TERMS) else 0.0
    profanity=1.0 if any(re.search(r'\b'+re.escape(t)+r'\b',low) for t in PROFANE) else 0.0
    bullying=.90 if any(t in low for t in BULLYING_TERMS) else 0.0
    severe=1.0 if any(t in low for t in SEVERE_ABUSE_TERMS) else 0.0
    grooming=1.0 if any(re.search(p,low) for p in GROOMING_PATTERNS) else 0.0

    if enabled():
        try:
            remote=normalize_signals(moderate_text(text),category='TEXT')
            remote['adult_score']=max(float(remote.get('adult_score',0)),adult)
            remote['sexual_score']=max(float(remote.get('sexual_score',0)),adult)
            remote['toxicity_score']=max(float(remote.get('toxicity_score',0)),profanity,bullying,severe,grooming)
            remote['general_score']=max(float(remote.get('general_score',0)),remote['adult_score'],remote['toxicity_score'])
            if grooming:remote['category']='GROOMING'
            elif severe:remote['category']='SEVERE_ABUSE'
            elif adult:remote['category']='SEXUAL_LANGUAGE'
            elif bullying:remote['category']='CYBERBULLYING'
            remote['deterministic_grooming']=bool(grooming)
            remote['deterministic_severe_abuse']=bool(severe)
            return normalize_signals(remote,category='TEXT')
        except Exception:
            # Continue with local deterministic/ML checks rather than silently
            # downgrading the message because a remote service failed.
            pass

    toxicity=max(profanity,bullying,severe,grooming);sexual=adult;ran=0;errors=[];extras={}
    if text:
        try:
            scores=timed_call('detoxify',lambda:_detox_scores(text),timeout_seconds('detoxify',90));ran+=1
            toxicity=max([toxicity]+[float(v) for v in scores.values()])
            sexual=max(float(scores.get('sexual_explicit',0) or 0),adult)
            extras['detoxify_scores']={k:float(v) for k,v in scores.items()}
        except Exception as exc:errors.append('detoxify_timeout' if 'timeout' in str(exc) else 'detoxify')
        if env_flag('LITTLENET_ENABLE_TEXT_CLASSIFIER'):
            try:
                h=timed_call('text_classifier',lambda:_optional_hf_scores(text),timeout_seconds('text_classifier',90));ran+=1
                if h:toxicity=max(toxicity,float(h.get('toxicity',0)));extras['text_classifier_scores']=h.get('labels',{})
            except Exception as exc:errors.append('text_classifier_timeout' if 'timeout' in str(exc) else 'text_classifier')

    if grooming:category='GROOMING'
    elif severe:category='SEVERE_ABUSE'
    elif sexual>=.4:category='SEXUAL_LANGUAGE'
    elif bullying>=.6:category='CYBERBULLYING'
    else:category='TEXT'

    result={
        'adult_score':sexual,'sexual_score':sexual,'violence_score':severe,'weapon_score':0,
        'toxicity_score':toxicity,'general_score':max(sexual,toxicity,severe),'category':category,
        'deterministic_grooming':bool(grooming),'deterministic_severe_abuse':bool(severe),
        'total_safety_failure':bool(text) and ran==0 and adult==0 and bullying==0 and profanity==0 and severe==0 and grooming==0,
        'partial_safety_failure':bool(text) and bool(errors) and (ran>0 or adult>0 or bullying>0 or profanity>0 or severe>0 or grooming>0),
        'errors':errors,**extras
    }
    return normalize_signals(result,category='TEXT')
