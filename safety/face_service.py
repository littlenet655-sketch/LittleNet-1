import json, math, os
from .common import timed_call,timeout_seconds
from database.connection import fetch_one, execute


def _face_match_threshold() -> float:
    """Return a deployment-tunable threshold that can only tighten the reviewed default."""
    try:
        configured = float(os.getenv('LITTLENET_FACE_MATCH_MAX_DISTANCE', '0.35'))
    except ValueError:
        configured = 0.35
    if not math.isfinite(configured):
        configured = 0.35
    return max(0.10, min(configured, 0.35))


def _validated_embedding(values):
    if not isinstance(values,(list,tuple)) or not values:raise ValueError('embedding_missing')
    if len(values) != 512: raise ValueError('invalid_embedding_dimensions')
    out=[]
    for value in values:
        if isinstance(value,bool):raise ValueError('embedding_invalid')
        try:
            value=float(value)
        except (TypeError, ValueError):
            raise ValueError('embedding_invalid')
        if not math.isfinite(value):raise ValueError('embedding_invalid')
        out.append(value)
    if not any(abs(x)>1e-12 for x in out):raise ValueError('embedding_invalid')
    return out



def _embedding(img_path):
    from .remote_client import enabled, face_embedding
    if enabled(): return _validated_embedding(face_embedding(img_path))
    # pyrefly: ignore [missing-import]
    from deepface import DeepFace  # type: ignore
    def run():
        faces=DeepFace.extract_faces(img_path=img_path, detector_backend='opencv', anti_spoofing=True, enforce_detection=True)
        if not isinstance(faces,list) or len(faces)!=1:raise ValueError('single_face_required')
        if faces[0].get('is_real') is not True:raise ValueError('liveness_failed')
        reps=DeepFace.represent(img_path=img_path, model_name='Facenet512', detector_backend='opencv', enforce_detection=True)
        if not isinstance(reps,list) or len(reps)!=1:raise ValueError('single_face_required')
        return _validated_embedding(reps[0].get('embedding'))
    return timed_call('deepface',run,timeout_seconds('deepface',120))


def has_face_profile(child_id: int) -> bool:
    """Check if child already has an active enrolled face profile."""
    row = fetch_one("SELECT 1 FROM face_profiles WHERE child_id=%s AND embedding IS NOT NULL", (int(child_id),))
    return bool(row)


def clear_child_face(child_id: int) -> bool:
    """Clear enrolled face profile upon authorized parent reset."""
    execute("DELETE FROM face_profiles WHERE child_id=%s", (int(child_id),))
    return True


def enroll(child_id, path, model_name='Facenet512'):
    if model_name != 'Facenet512':
        raise ValueError('invalid_model_name')
    emb = _embedding(path)
    emb = _validated_embedding(emb)
    execute('''INSERT INTO face_profiles(child_id,embedding,model_name,reference_path)
               VALUES(%s,%s::jsonb,'Facenet512',%s)
               ON CONFLICT(child_id) DO UPDATE SET embedding=EXCLUDED.embedding,model_name=EXCLUDED.model_name,reference_path=EXCLUDED.reference_path,updated_at=NOW()''',
            (child_id, json.dumps(emb), None))
    return True


def verify(child_id,path):
    row=fetch_one('SELECT embedding, model_name FROM face_profiles WHERE child_id=%s',(child_id,))
    if not row: return False,'not_enrolled',None
    if row.get('model_name') != 'Facenet512':
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,NULL,%s)',(child_id,'invalid_enrolled_model'))
        return False,'invalid_enrolled_model',None
    ref=row.get('embedding')
    if ref is None: return False,'not_enrolled',None
    try:
        ref=json.loads(ref) if isinstance(ref,str) else ref
        ref=_validated_embedding(ref)
    except Exception:

        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,NULL,%s)',(child_id,'invalid_enrolled_embedding'))
        return False,'invalid_enrolled_embedding',None
    try:
        from .remote_client import enabled, face_verify
        if enabled():
            remote=face_verify(ref,path)
            if remote.get('ok') is not True:
                reason=remote.get('reason','face_error')
                execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,FALSE,%s,%s,%s)',(child_id,False if reason=='liveness_failed' else None,remote.get('distance'),reason))
                return False,reason,remote.get('distance')
            dist=float(remote['distance'])
            # Re-apply the authoritative server threshold locally. A remote
            # provider may tighten it, but can never silently weaken it.
            ok=remote.get('matched') is True and dist < _face_match_threshold()
            execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
            return ok,'matched' if ok else 'not_matched',dist
        test=_embedding(path)
    except Exception as e:
        reason='liveness_failed' if 'liveness' in str(e).lower() or 'spoof' in str(e).lower() or 'single_face' in str(e).lower() else 'face_error'
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,%s,%s)',(child_id,False if reason=='liveness_failed' else None,reason))
        return False,reason,None
    if len(ref)!=len(test):
        execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,reason) VALUES(%s,FALSE,TRUE,%s)',(child_id,'embedding_mismatch'))
        return False,'face_error',None
    dot=sum(a*b for a,b in zip(ref,test)); nr=math.sqrt(sum(a*a for a in ref)); nt=math.sqrt(sum(b*b for b in test)); dist=1-(dot/(nr*nt+1e-9)); ok=dist<_face_match_threshold()
    execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
    return ok,'matched' if ok else 'not_matched',dist


def verify_adult_face(img_path):
    """Estimate adult status only after explicit single-face liveness evidence."""
    from .remote_client import enabled, face_adult_verify
    try:
        auto_approve_age=max(18.0,float(os.getenv('GUARDIAN_FACE_AUTO_APPROVE_AGE','25')))
    except ValueError:
        auto_approve_age=25.0
    if enabled():
        try:
            result=face_adult_verify(img_path)
            if isinstance(result,dict) and result.get('is_adult') in {True,False}:
                age=result.get('estimated_age')
                if result.get('is_adult') is True and (isinstance(age,bool) or not isinstance(age,(int,float)) or float(age)<auto_approve_age):
                    return {'is_adult':False,'estimated_age':age,'method':result.get('method','REMOTE_AI'),'reason':'age_estimate_ambiguous','requires_manual_review':True}
                return result
            return {
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
        # pyrefly: ignore [missing-import]
        from deepface import DeepFace  # type: ignore
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
    except Exception as exc:
        msg = str(exc).lower()
        if 'could not be detected' in msg or 'confirm that the picture is a face' in msg or 'no face' in msg:
            return {'is_adult': False, 'estimated_age': None, 'method': 'ANTI_SPOOF', 'reason': 'single_face_required'}
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
        if age_val>=auto_approve_age:
            return {'is_adult': True, 'estimated_age': age_display, 'method': 'DEEPFACE'}
        if age_val>=18.0:
            return {'is_adult':False,'estimated_age':age_display,'method':'DEEPFACE','reason':'age_estimate_ambiguous','requires_manual_review':True}
        return {'is_adult': False, 'estimated_age': age_display, 'method': 'DEEPFACE', 'reason': 'under_age'}
    except Exception as exc:
        msg = str(exc).lower()
        if 'could not be detected' in msg or 'single_face_required' in msg:
            return {'is_adult': False, 'estimated_age': None, 'method': 'DEEPFACE', 'reason': 'single_face_required'}

    # Optional age fallback is allowed only after the explicit anti-spoof check above passed.
    allow_fallback=os.getenv('LITTLENET_ENABLE_GENERATIVE_AGE_FALLBACK','0').strip().lower() in {'1','true','yes','on'}
    api_key = (os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')) if allow_fallback else None
    if api_key:
        try:
            # pyrefly: ignore [missing-import]
            import google.generativeai as genai  # type: ignore
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
                is_adult = data.get('is_adult') is True and age_val >= auto_approve_age
                return {
                    'is_adult': is_adult,
                    'estimated_age': age_int,
                    'method': 'GEMINI_VISION',
                    'reason': None if is_adult else ('age_estimate_ambiguous' if age_val>=18.0 else 'under_age'),
                    'requires_manual_review':bool(not is_adult and age_val>=18.0),
                }
        except Exception:
            pass

    return {
        'is_adult': False,
        'estimated_age': None,
        'method': 'UNAVAILABLE',
        'reason': 'age_verification_unavailable',
    }
