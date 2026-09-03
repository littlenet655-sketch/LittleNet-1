"""Standalone LittleNet AI inference service.

Deploy this separately from the lightweight web application when the web host has
low RAM. It does not need database access and never stores uploaded media.
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
from safety.audio_service import check_audio
from safety.visual_service import check_image, check_video

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 100 * 1024 * 1024


def authorized():
    # Fail closed: the heavy inference API must never become public just because
    # a deployment forgot to configure its shared secret.
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
    return jsonify({"ok": True, "service": "littlenet-ai"})


@app.post("/ai/moderate")
def moderate():
    if not authorized(): return deny()
    t = (request.form.get("content_type") or "").upper()
    if t == "TEXT":
        return jsonify({"ok": True, "signals": check_text(request.form.get("text", ""))})
    path = None
    try:
        path = save_upload()
        if t in {"AUDIO", "VOICE"}: signals = check_audio(path)
        elif t == "VIDEO": signals = check_video(path)
        elif t == "IMAGE": signals = check_image(path)
        else: return jsonify({"ok": False, "error": "unsupported_content_type"}), 400
        return jsonify({"ok": True, "signals": signals})
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

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8081")))
