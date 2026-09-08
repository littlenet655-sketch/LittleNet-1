import json, math
from .common import timed_call,timeout_seconds
from database.connection import fetch_one, execute


def _validated_embedding(values):
    if not isinstance(values,(list,tuple)) or not values:raise ValueError('embedding_missing')
    out=[]
    for value in values:
        if isinstance(value,bool):raise ValueError('embedding_invalid')
        value=float(value)
        if not math.isfinite(value):raise ValueError('embedding_invalid')
        out.append(value)
    if not any(abs(x)>1e-12 for x in out):raise ValueError('embedding_invalid')
    return out


def _embedding(img_path):
    from .remote_client import enabled, face_embedding
    if enabled(): return _validated_embedding(face_embedding(img_path))
    from deepface import DeepFace
    def run():
        faces=DeepFace.extract_faces(img_path=img_path, detector_backend='opencv', anti_spoofing=True, enforce_detection=True)
        if not isinstance(faces,list) or len(faces)!=1:raise ValueError('single_face_required')
        if faces[0].get('is_real') is not True:raise ValueError('liveness_failed')
        reps=DeepFace.represent(img_path=img_path, model_name='Facenet512', detector_backend='opencv', enforce_detection=True)
        if not isinstance(reps,list) or len(reps)!=1:raise ValueError('single_face_required')
        return _validated_embedding(reps[0].get('embedding'))
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
        ref=_validated_embedding(ref)
        if enabled():
            remote=face_verify(ref,path)
            if remote.get('ok') is not True:
                reason=remote.get('reason','face_error')
                execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,FALSE,%s,%s,%s)',(child_id,False if reason=='liveness_failed' else None,remote.get('distance'),reason))
                return False,reason,remote.get('distance')
            dist=float(remote['distance']);ok=remote.get('matched') is True
            execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
            return ok,'matched' if ok else 'not_matched',dist
        test=_embedding(path)
    except Exception as e:
        reason='liveness_failed' if 'liveness' in str(e).lower() or 'spoof' in str(e).lower() or 'single_face' in str(e).lower() else 'face_error'
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,%s,%s)',(child_id,False if reason=='liveness_failed' else None,reason)); return False,reason,None
    if len(ref)!=len(test):
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,TRUE,%s)',(child_id,'embedding_mismatch'))
        return False,'face_error',None
    dot=sum(a*b for a,b in zip(ref,test)); nr=math.sqrt(sum(a*a for a in ref)); nt=math.sqrt(sum(b*b for b in test)); dist=1-(dot/(nr*nt+1e-9)); ok=dist<0.35
    execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
    return ok,'matched' if ok else 'not_matched',dist


def verify_adult_face(img_path):
    """Estimate adult status only after explicit single-face liveness evidence."""
    import os

    from .remote_client import enabled, face_adult_verify
    if enabled():
        try:
            result=face_adult_verify(img_path)
            return result if isinstance(result,dict) and result.get('is_adult') in {True,False} else {
                'is_adult':False,'estimated_age':None,'method':'REMOTE_AI','reason':'adult_face_verification_invalid'
            }
        except Exception:
            return {
                'is_adult': False,
                'estimated_age': None,
                'method': 'REMOTE_AI',
                'reason': 'adult_face_service_unavailable',
            }

    try:
        from deepface import DeepFace
        faces = DeepFace.extract_faces(
            img_path=img_path,
            detector_backend='opencv',
            anti_spoofing=True,
            enforce_detection=True,
        )
        if not isinstance(faces,list) or len(faces)!=1:
            return {'is_adult':False,'estimated_age':None,'method':'ANTI_SPOOF','reason':'single_face_required'}
        if faces[0].get('is_real') is not True:
            return {'is_adult': False, 'estimated_age': None, 'method': 'ANTI_SPOOF', 'reason': 'liveness_failed'}
    except Exception:
        return {'is_adult': False, 'estimated_age': None, 'method': 'ANTI_SPOOF', 'reason': 'liveness_unavailable'}

    try:
        analysis = DeepFace.analyze(
            img_path=img_path,
            actions=['age'],
            detector_backend='opencv',
            enforce_detection=True,
        )
        if not isinstance(analysis,list) or len(analysis)!=1:
            raise ValueError('single_face_required')
        raw_age=analysis[0].get('age')
        if isinstance(raw_age,bool):raise ValueError('age_invalid')
        age_val=float(raw_age)
        if not math.isfinite(age_val) or age_val<=0:raise ValueError('age_invalid')
        age_display=int(round(age_val))
        if age_val>=18.0:
            return {'is_adult': True, 'estimated_age': age_display, 'method': 'DEEPFACE'}
        return {'is_adult': False, 'estimated_age': age_display, 'method': 'DEEPFACE', 'reason': 'under_age'}
    except Exception:
        pass

    # Optional age fallback is allowed only after the explicit anti-spoof check above passed.
    api_key = os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
    if api_key:
        try:
            import google.generativeai as genai
            from PIL import Image
            genai.configure(api_key=api_key)
            model = genai.GenerativeModel('gemini-1.5-flash')
            img = Image.open(img_path)
            prompt = (
                'Estimate whether the person is 18 or older. '
                'Return only JSON like {"is_adult": true, "estimated_age": 30}.'
            )
            resp = model.generate_content([prompt, img])
            text = resp.text.strip()
            if '{' in text and '}' in text:
                data = json.loads(text[text.find('{'):text.rfind('}')+1])
                try:
                    age_val = float(data['estimated_age'])
                except (KeyError, TypeError, ValueError):
                    return {
                        'is_adult': False,
                        'estimated_age': None,
                        'method': 'GEMINI_VISION',
                        'reason': 'age_verification_unavailable',
                    }
                if not math.isfinite(age_val) or age_val < 0:
                    return {
                        'is_adult': False,
                        'estimated_age': None,
                        'method': 'GEMINI_VISION',
                        'reason': 'age_verification_unavailable',
                    }
                age_int = int(round(age_val))
                is_adult = data.get('is_adult') is True and age_val >= 18.0
                return {
                    'is_adult': is_adult,
                    'estimated_age': age_int,
                    'method': 'GEMINI_VISION',
                    'reason': None if is_adult else 'under_age',
                }
        except Exception:
            pass

    return {
        'is_adult': False,
        'estimated_age': None,
        'method': 'UNAVAILABLE',
        'reason': 'age_verification_unavailable',
    }
