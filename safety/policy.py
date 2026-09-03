from dataclasses import dataclass

ADULT_CATEGORIES={'ADULT','SEXUAL','NSFW','NUDITY','EXPLICIT','SEXUAL_LANGUAGE'}
@dataclass(frozen=True)
class Decision:
    action:str; risk:float; reason:str

def decide(signals:dict, safety_level='STRICT', adult_threshold=0.40):
    adult=max(float(signals.get('adult_score',0)), float(signals.get('sexual_score',0)))
    weapon=float(signals.get('weapon_score',0)); violence=float(signals.get('violence_score',0)); toxicity=float(signals.get('toxicity_score',0))
    category=str(signals.get('category','')).upper()
    total_failure=bool(signals.get('total_safety_failure'))
    partial_failure=bool(signals.get('partial_safety_failure'))
    # HARD BLOCKS ALWAYS WIN. Model outages never downgrade positive evidence.
    if total_failure: return Decision('BLOCK',100.0,'AI safety unavailable: fail closed')
    if adult >= adult_threshold or category in ADULT_CATEGORIES: return Decision('BLOCK',max(adult*100,90),'18+ content hard blocked')
    if weapon >= .45 or category=='WEAPON': return Decision('BLOCK',max(weapon*100,85),'weapon/dangerous object')
    level={'STANDARD':(.78,.58),'STRICT':(.68,.48),'VERY_STRICT':(.58,.38)}.get(safety_level, (.68,.48))
    block_t, review_t=level
    risk=max(violence,toxicity,float(signals.get('general_score',0)))
    if risk>=block_t: return Decision('BLOCK',risk*100,'high safety risk')
    if partial_failure: return Decision('REVIEW',max(risk*100,50),'incomplete AI result: parent review')
    if risk>=review_t: return Decision('REVIEW',risk*100,'medium safety risk')
    return Decision('ALLOW',risk*100,'safe under current policy')
