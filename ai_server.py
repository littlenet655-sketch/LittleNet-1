"""Standalone LittleNet heavy AI inference service.

The locked LittleNet scope supports TEXT, IMAGE and VIDEO moderation plus face
verification. Standalone audio/voice moderation is intentionally not exposed.
"""
import json
import math
import os
import tempfile
import hmac
from pathlib import Path

os.environ["LITTLENET_AI_SERVER"] = "1"

from flask import Flask, jsonify, request

from safety.text_service import check_text
from safety.visual_service import check_image
from safety.video_service import check_video

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 100 * 1024 * 1024


def authorized():
    secret = os.getenv("AI_SHARED_SECRET", "").strip()
    supplied = request.headers.get("X-LittleNet-AI-Key", "")
    return bool(secret) and hmac.compare_digest(supplied, secret)


def deny():
    return jsonify({"ok": False, "error": "unauthorized"}), 401


def save_upload():
    f = request.files.get("file")
    if not f or not f.filename:
        raise ValueError("file_required")
    suffix = Path(f.filename).suffix[:12]
    fd, path = tempfile.mkstemp(suffix=suffix)
    os.close(fd)
    f.save(path)
    return path


@app.get("/healthz")
def healthz():
    if not authorized(): return deny()
    return jsonify({"ok": True, "service": "littlenet-ai", "moderation": ["TEXT", "IMAGE", "VIDEO"]})


def _sanitize(val):
    if isinstance(val, dict): return {k: _sanitize(v) for k, v in val.items()}
    if isinstance(val, (list, tuple)): return [_sanitize(v) for v in val]
    if hasattr(val, 'item'): return val.item()
    return val


@app.post("/ai/moderate")
def moderate():
    if not authorized(): return deny()
    t = (request.form.get("content_type") or "").upper()
    if t == "TEXT":
        return jsonify({"ok": True, "signals": _sanitize(check_text(request.form.get("text", "")))})
    if t not in {"IMAGE", "VIDEO"}:
        return jsonify({"ok": False, "error": "unsupported_content_type"}), 400
    path = None
    try:
        path = save_upload()
        signals = check_video(path) if t == "VIDEO" else check_image(path)
        return jsonify({"ok": True, "signals": _sanitize(signals)})
    finally:
        if path:
            try: os.unlink(path)
            except OSError: pass


@app.post("/ai/rank")
def rank_endpoint():
    if not authorized(): return deny()
    data=request.get_json(silent=True) or {}
    profile_text=str(data.get("profile_text") or "")[:500]
    raw=data.get("items") or []
    if not isinstance(raw,list) or len(raw)>60:
        return jsonify({"ok":False,"error":"invalid_items"}),400
    items=[]
    for x in raw:
        if not isinstance(x,dict):continue
        try:item_id=int(x.get("id"))
        except (TypeError,ValueError):continue
        items.append({"id":item_id,"text":str(x.get("text") or "")[:500]})
    try:
        from safety.semantic_service import rank_texts
        scores=rank_texts(profile_text,[x["text"] for x in items])
        ranked=[{"id":x["id"],"score":float(score)} for x,score in zip(items,scores)]
        ranked.sort(key=lambda x:x["score"],reverse=True)
        return jsonify({"ok":True,"items":ranked})
    except Exception:
        app.logger.exception("semantic ranking failed")
        return jsonify({"ok":False,"error":"ranking_unavailable"}),503


@app.post("/ai/face/embedding")
def face_embedding_endpoint():
    if not authorized(): return deny()
    path = None
    try:
        path = save_upload()
        from safety.face_service import _embedding
        emb = _embedding(path)
        return jsonify({"ok": True, "embedding": emb})
    except Exception as exc:
        reason = "liveness_failed" if any(k in str(exc).lower() for k in ("liveness", "spoof", "real")) else "face_error"
        return jsonify({"ok": False, "reason": reason}), 422
    finally:
        if path:
            try: os.unlink(path)
            except OSError: pass


@app.post("/ai/face/verify")
def face_verify_endpoint():
    if not authorized(): return deny()
    path = None
    try:
        reference = [float(x) for x in json.loads(request.form["reference"])]
        path = save_upload()
        from safety.face_service import _embedding
        test = _embedding(path)
        dot = sum(a*b for a,b in zip(reference,test))
        nr = math.sqrt(sum(a*a for a in reference)); nt = math.sqrt(sum(b*b for b in test))
        dist = 1-(dot/(nr*nt+1e-9)); matched = dist < 0.35
        return jsonify({"ok": True, "matched": matched, "distance": dist})
    except Exception as exc:
        reason = "liveness_failed" if any(k in str(exc).lower() for k in ("liveness", "spoof", "real")) else "face_error"
        return jsonify({"ok": False, "reason": reason}), 422
    finally:
        if path:
            try: os.unlink(path)
            except OSError: pass


@app.post("/ai/face/adult")
def face_adult_endpoint():
    if not authorized(): return deny()
    path = None
    try:
        path = save_upload()
        from safety.face_service import verify_adult_face
        result = verify_adult_face(path)
        return jsonify({"ok": True, "result": _sanitize(result)})
    except Exception as exc:
        reason = "liveness_failed" if any(k in str(exc).lower() for k in ("liveness", "spoof", "real")) else "adult_face_error"
        return jsonify({"ok": False, "reason": reason}), 422
    finally:
        if path:
            try: os.unlink(path)
            except OSError: pass



@app.post("/ai/jobs/process-media")
def process_media_job_endpoint():
    """Receiver endpoint for QStash background media processing dispatch.

    Verifies Upstash signature using QSTASH_CURRENT_SIGNING_KEY / QSTASH_NEXT_SIGNING_KEY,
    with defense-in-depth AI_SHARED_SECRET fallback. Rejects unauthenticated requests.
    """
    from services.qstash_verifier import verify_qstash_signature

    current_key = (os.getenv("QSTASH_CURRENT_SIGNING_KEY") or "").strip()
    next_key = (os.getenv("QSTASH_NEXT_SIGNING_KEY") or "").strip()
    signature = request.headers.get("Upstash-Signature", "").strip()

    is_signed_qstash = bool(
        current_key
        and signature
        and verify_qstash_signature(
            body=request.data,
            signature=signature,
            current_key=current_key,
            next_key=next_key,
            url=request.base_url,
        )
    )
    is_shared_secret = authorized()

    if not (is_signed_qstash or is_shared_secret):
        return jsonify(
            {
                "ok": False,
                "error": "unauthorized",
                "message": "Invalid or missing QStash signature",
            }
        ), 401

    data = request.get_json(silent=True) or {}
    payload = data.get("payload") if isinstance(data.get("payload"), dict) else data

    post_id = payload.get("post_id")
    child_id = payload.get("child_id")
    object_key = payload.get("object_key")
    kind = payload.get("kind", "post")

    if not (post_id and child_id and object_key):
        return jsonify({"ok": False, "error": "missing_required_payload_fields"}), 400

    from services.media_processor import process_media_job

    res = process_media_job(int(post_id), int(child_id), str(object_key), str(kind))
    return jsonify({"ok": True, "result": res}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8081")))