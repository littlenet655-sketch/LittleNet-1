import json, math
from .common import timed_call,timeout_seconds
from database.connection import fetch_one, execute

def _embedding(img_path):
    from .remote_client import enabled, face_embedding
    if enabled(): return face_embedding(img_path)
    from deepface import DeepFace
    def run():
        faces=DeepFace.extract_faces(img_path=img_path, detector_backend='opencv', anti_spoofing=True, enforce_detection=True)
        if not faces or not all(bool(f.get('is_real',False)) for f in faces): raise ValueError('liveness_failed')
        reps=DeepFace.represent(img_path=img_path, model_name='Facenet512', detector_backend='opencv', enforce_detection=True)
        return [float(x) for x in reps[0]['embedding']]
    return timed_call('deepface',run,timeout_seconds('deepface',120))

def enroll(child_id,path):
    emb=_embedding(path)
    execute('''INSERT INTO face_profiles(child_id,embedding,reference_path) VALUES(%s,%s::jsonb,%s) ON CONFLICT(child_id) DO UPDATE SET embedding=EXCLUDED.embedding,reference_path=EXCLUDED.reference_path,updated_at=NOW()''',(child_id,json.dumps(emb),None))
    return True

def verify(child_id,path):
    row=fetch_one('SELECT embedding FROM face_profiles WHERE child_id=%s',(child_id,))
    if not row: return False,'not_enrolled',None
    try:
        from .remote_client import enabled, face_verify
        ref=row['embedding']; ref=json.loads(ref) if isinstance(ref,str) else ref
        if enabled():
            remote=face_verify(ref,path)
            if not remote.get('ok'):
                reason=remote.get('reason','face_error')
                execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,FALSE,%s,%s,%s)',(child_id,False if reason=='liveness_failed' else None,remote.get('distance'),reason))
                return False,reason,remote.get('distance')
            dist=float(remote['distance']);ok=bool(remote['matched'])
            execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
            return ok,'matched' if ok else 'not_matched',dist
        test=_embedding(path)
    except Exception as e:
        reason='liveness_failed' if 'liveness' in str(e).lower() or 'spoof' in str(e).lower() else 'face_error'
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,%s,%s)',(child_id,False if reason=='liveness_failed' else None,reason)); return False,reason,None
    ref=row['embedding']; ref=json.loads(ref) if isinstance(ref,str) else ref
    dot=sum(a*b for a,b in zip(ref,test)); nr=math.sqrt(sum(a*a for a in ref)); nt=math.sqrt(sum(b*b for b in test)); dist=1-(dot/(nr*nt+1e-9)); ok=dist<0.35
    execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
    return ok,'matched' if ok else 'not_matched',dist
