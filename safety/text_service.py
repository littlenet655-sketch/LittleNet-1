import os,re
from .common import env_flag,normalize_signals,timed_call,timeout_seconds
ADULT_TERMS={'porn','pornography','nude','nudes','sex video','xxx','send nudes','sexual photo','explicit photo','onlyfans','sexting'}
PROFANE={'fuck','bitch','asshole'}
BULLYING_TERMS={
    'kill yourself','nobody likes you','you are ugly','you are stupid','you are useless',
    'loser','idiot','worthless','go die','hate you','shut up','no one wants you','everyone hates you'
}
_DETOX=None;_HF_TEXT=None

def _detox_scores(text):
    global _DETOX
    from detoxify import Detoxify
    model_name=os.getenv('LITTLENET_DETOXIFY_MODEL','multilingual').strip() or 'multilingual'
    if _DETOX is None:_DETOX=Detoxify(model_name)
    return _DETOX.predict(text) if text else {}

def _optional_hf_scores(text):
    """Optional hate/self-harm/bullying classifier.

    Enable with LITTLENET_ENABLE_TEXT_CLASSIFIER=1 and set
    LITTLENET_TEXT_SAFETY_MODEL to a Hugging Face text-classification model.
    """
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
    if enabled():
        try:return normalize_signals(moderate_text(text),category='TEXT')
        except Exception:return normalize_signals({'category':'TEXT','total_safety_failure':True,'errors':['remote_ai_unavailable']},category='TEXT')
    text=(text or '').strip();low=text.lower()
    adult=1.0 if any(t in low for t in ADULT_TERMS) else 0.0
    profanity=1.0 if any(re.search(r'\b'+re.escape(t)+r'\b',low) for t in PROFANE) else 0.0
    bullying=.86 if any(t in low for t in BULLYING_TERMS) else 0.0
    toxicity=max(profanity,bullying);sexual=adult;ran=0;errors=[];extras={}
    if text:
        try:
            scores=timed_call('detoxify',lambda:_detox_scores(text),timeout_seconds('detoxify',90));ran+=1
            toxicity=max([float(v) for v in scores.values()] or [toxicity],toxicity)
            sexual=max(float(scores.get('sexual_explicit',0) or 0),adult)
            extras['detoxify_scores']=scores
        except Exception as exc:errors.append('detoxify_timeout' if 'timeout' in str(exc) else 'detoxify')
        if env_flag('LITTLENET_ENABLE_TEXT_CLASSIFIER'):
            try:
                h=timed_call('text_classifier',lambda:_optional_hf_scores(text),timeout_seconds('text_classifier',90));ran+=1
                if h:toxicity=max(toxicity,float(h.get('toxicity',0)));extras['text_classifier_scores']=h.get('labels',{})
            except Exception as exc:errors.append('text_classifier_timeout' if 'timeout' in str(exc) else 'text_classifier')
    category='SEXUAL_LANGUAGE' if sexual>=.4 else ('CYBERBULLYING' if bullying>=.6 else 'TEXT')
    result={
        'adult_score':sexual,'sexual_score':sexual,'violence_score':0,'weapon_score':0,
        'toxicity_score':toxicity,'general_score':max(sexual,toxicity),'category':category,
        'total_safety_failure':bool(text) and ran==0 and adult==0 and bullying==0 and profanity==0,
        'partial_safety_failure':bool(text) and bool(errors) and (ran>0 or adult>0 or bullying>0 or profanity>0),
        'errors':errors,**extras
    }
    return normalize_signals(result,category='TEXT')
