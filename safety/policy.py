from dataclasses import dataclass

ADULT_CATEGORIES={'ADULT','SEXUAL','NSFW','NUDITY','EXPLICIT','SEXUAL_LANGUAGE'}
HARD_TEXT_CATEGORIES={'GROOMING','SEVERE_ABUSE'}

@dataclass(frozen=True)
class Decision:
    action:str; risk:float; reason:str

def decide(signals:dict, safety_level='STRICT', adult_threshold=0.40):
    adult=max(float(signals.get('adult_score',0)),float(signals.get('sexual_score',0)))
    weapon=float(signals.get('weapon_score',0));violence=float(signals.get('violence_score',0));toxicity=float(signals.get('toxicity_score',0))
    category=str(signals.get('category','')).upper()
    total_failure=bool(signals.get('total_safety_failure'));partial_failure=bool(signals.get('partial_safety_failure'))

    # Deterministic child-safety hard blocks always win, even if another model fails.
    if category in HARD_TEXT_CATEGORIES or signals.get('deterministic_grooming') or signals.get('deterministic_severe_abuse'):
        reason='grooming/coercion hard blocked' if category=='GROOMING' or signals.get('deterministic_grooming') else 'severe abuse/threat hard blocked'
        return Decision('BLOCK',100.0,reason)
    if total_failure: return Decision('BLOCK',100.0,'AI safety unavailable: fail closed')

    # Visual NSFW models have different score calibration. For IMAGE/VIDEO model
    # diagnostics, use model-specific thresholds before the generic adult score.
    visual_nsfw=None
    if signals.get('model_signals') and category in {'IMAGE','VIDEO','ADULT','NSFW','NUDITY','EXPLICIT'}:
        try:
            from .nsfw_policy import classify_signals as classify_nsfw
            visual_nsfw=classify_nsfw(signals)
        except Exception:
            visual_nsfw=None
    if visual_nsfw and visual_nsfw.get('has_evidence'):
        top=visual_nsfw.get('top') or {}
        if visual_nsfw.get('block'):
            return Decision('BLOCK',max(float(top.get('score',0))*100,90),f"18+ visual content hard blocked: {top.get('model','nsfw')} evidence")
        if visual_nsfw.get('review'):
            return Decision('REVIEW',max(float(top.get('score',0))*100,50),f"possible 18+ visual content requires parent review: {top.get('model','nsfw')} evidence")
    elif adult >= adult_threshold or category in ADULT_CATEGORIES:
        return Decision('BLOCK',max(adult*100,90),'18+ content hard blocked')

    # Do not rely only on the legacy weapon_score mapping. Inspect raw YOLO
    # detections as well so OpenImages labels such as Axe, Handgun and Kitchen
    # knife receive the same child-safety policy. Medium-confidence evidence goes
    # to Parent Review instead of being silently allowed.
    try:
        from .yolo_policy import classify_signals
        yolo=classify_signals(signals)
    except Exception:
        yolo={'score':0.0,'block':False,'review':False,'dangerous':[]}
    weapon=max(weapon,float(yolo.get('score',0) or 0))
    if yolo.get('block') or weapon>=.45 or category=='WEAPON':
        label=((yolo.get('dangerous') or [{}])[0].get('label') or 'dangerous object')
        return Decision('BLOCK',max(weapon*100,85),f'weapon/dangerous object: {label}')
    if yolo.get('review'):
        label=((yolo.get('dangerous') or [{}])[0].get('label') or 'dangerous object')
        return Decision('REVIEW',max(weapon*100,50),f'possible dangerous object requires parent review: {label}')

    block_t,review_t={'STANDARD':(.78,.58),'STRICT':(.68,.48),'VERY_STRICT':(.58,.38)}.get(safety_level,(.68,.48))
    risk=max(violence,toxicity,float(signals.get('general_score',0)))
    if risk>=block_t:return Decision('BLOCK',risk*100,'high safety risk')
    if partial_failure:return Decision('REVIEW',max(risk*100,50),'incomplete AI result: parent review')
    if risk>=review_t:return Decision('REVIEW',risk*100,'medium safety risk')
    return Decision('ALLOW',risk*100,'safe under current policy')
