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
    dot=sum(a*b for a,b in zip(ref,test)); nr=math.sqrt(sum(a*a for a in ref)); nt=math.sqrt(sum(b*b for b in test)); dist=1-(dot/(nr*nt+1e-9)); ok=dist<0.35
    execute('INSERT INTO face_login_attempts(child_id,success,liveness_passed,distance,reason) VALUES(%s,%s,TRUE,%s,%s)',(child_id,ok,dist,'matched' if ok else 'not_matched'))
    return ok,'matched' if ok else 'not_matched',dist


def verify_adult_face(img_path):
    """Estimate adult status from a live anti-spoofed selfie and fail closed."""
    import os

    # In split deployments the lightweight web image intentionally has no
    # DeepFace/TensorFlow. Delegate this expensive verification to the protected
    # AI service, which runs the exact same local implementation below.
    from .remote_client import enabled, face_adult_verify
    if enabled():
        try:
            return face_adult_verify(img_path)
        except Exception:
            return {
                'is_adult': False,
                'estimated_age': None,
                'method': 'REMOTE_AI',
                'reason': 'adult_face_service_unavailable',
            }

    # First require anti-spoof/liveness from DeepFace extraction. A static,
    # printed, or obviously spoofed face must never become a verified guardian.
    try:
        from deepface import DeepFace
        faces = None
        for enforce in (True, False):
            try:
                faces = DeepFace.extract_faces(
                    img_path=img_path,
                    detector_backend='opencv',
                    anti_spoofing=True,
                    enforce_detection=enforce,
                )
                if faces:
                    break
            except Exception:
                continue

        if faces and not all(bool(f.get('is_real', True)) for f in faces):
            return {'is_adult': False, 'estimated_age': None, 'method': 'ANTI_SPOOF', 'reason': 'liveness_failed'}
    except Exception:
        return {'is_adult': False, 'estimated_age': None, 'method': 'ANTI_SPOOF', 'reason': 'liveness_unavailable'}

    # Prefer local deterministic age analysis. This is only a safety gate; the
    # parent's declared DOB and consent are still required separately.
    try:
        analysis = None
        for enforce in (True, False):
            try:
                analysis = DeepFace.analyze(
                    img_path=img_path,
                    actions=['age'],
                    detector_backend='opencv',
                    enforce_detection=enforce,
                )
                if analysis and isinstance(analysis, list):
                    break
            except Exception:
                continue

        if analysis and isinstance(analysis, list):
            age = int(round(float(analysis[0].get('age', 0))))
            if age >= 18:
                return {'is_adult': True, 'estimated_age': age, 'method': 'DEEPFACE'}
            elif age > 0:
                return {'is_adult': False, 'estimated_age': age, 'method': 'DEEPFACE', 'reason': 'under_age'}
    except Exception:
        pass

    # Optional Gemini fallback if explicitly configured. It does not override a
    # failed anti-spoof check above.
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
                age = data.get('estimated_age')
                is_adult = bool(data.get('is_adult', False)) and (age is None or age >= 18)
                return {
                    'is_adult': is_adult,
                    'estimated_age': age,
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
