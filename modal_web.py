"""Optional Modal deployment for LittleNet's Flask/Jinja web application.

PostgreSQL remains external (Neon/etc.). Private media is stored in R2; the
legacy uploads volume remains only for compatibility with local/demo assets.
"""
from pathlib import Path
import os
import subprocess

import modal

ROOT = Path(__file__).resolve().parent
app = modal.App("littlenet-web")
uploads = modal.Volume.from_name("littlenet-uploads", create_if_missing=True)
web_secret = modal.Secret.from_name(
    "littlenet-web-secrets",
    required_keys=["DATABASE_URL", "SECRET_KEY", "AI_SERVICE_URL", "AI_SHARED_SECRET"],
)

web_image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg")
    .pip_install_from_requirements(str(ROOT / "requirements-safety.txt"))
    .run_commands("python -m spacy download en_core_web_sm")
    .workdir("/root/littlenet")
    .env(
        {
            "COOKIE_SECURE": "1",
            "LITTLENET_DEVICE": "cpu",
            "LITTLENET_ENABLE_PRESIDIO": "1",
            "LITTLENET_PRESIDIO_SPACY_MODEL": "en_core_web_sm",
            "LITTLENET_DEPLOY_VERSION": "4",
        }
    )
    .add_local_dir(
        str(ROOT),
        remote_path="/root/littlenet",
        ignore=[
            ".git/**", ".pytest_cache/**", "**/__pycache__/**", "uploads/**",
            "android/**", "tools/gradle-8.9/**", "node_modules/**", ".agent/**",
            ".agents/**", "agent/**", ".claude/**", ".cursor/**", "*.db",
            "*.zip", "*.apk", ".env",
        ],
        copy=True,
    )
)


@app.function(
    image=web_image,
    cpu=2.0,
    memory=2048,
    secrets=[web_secret],
    volumes={"/root/littlenet/uploads": uploads},
    timeout=300,
    startup_timeout=120,
    scaledown_window=600,
    min_containers=0,
    max_containers=1,
)
@modal.wsgi_app()
def web():
    """Expose the complete LittleNet Flask app on Modal."""
    os.chdir("/root/littlenet")
    Path("uploads").mkdir(parents=True, exist_ok=True)
    from flask import request
    from app import create_app

    flask_app = create_app()

    @flask_app.after_request
    def persist_upload_changes(response):
        if request.method in {"POST", "PUT", "PATCH", "DELETE"} and request.files:
            try:
                uploads.commit()
            except Exception:
                flask_app.logger.exception("Modal uploads Volume commit failed")
        return response

    return flask_app


@app.function(image=web_image, secrets=[web_secret], timeout=300)
def init_database():
    """Create/upgrade schema on the external PostgreSQL database."""
    os.chdir("/root/littlenet")
    subprocess.run(["python", "tools/init_db.py"], check=True)
    return {"ok": True}


@app.function(image=web_image, secrets=[web_secret], timeout=120)
def seed_quizzes():
    os.chdir("/root/littlenet")
    subprocess.run(["python", "tools/seed_quizzes.py"], check=True)
    return {"ok": True}


@app.function(image=web_image, secrets=[web_secret], timeout=120)
def web_preflight():
    """Verify DB, remote AI and local Presidio availability from Modal."""
    os.chdir("/root/littlenet")
    from database.connection import fetch_one
    from safety.remote_client import health
    from safety.presidio_adapter import analyze_pii

    db = fetch_one("SELECT 1 ok")
    ai = health()
    pii = analyze_pii("test@example.com")
    pii_ok = bool(pii.get("available") and "EMAIL_ADDRESS" in pii.get("categories", []))
    return {
        "ok": bool(db and db["ok"] == 1 and ai.get("ok") and pii_ok),
        "database": True,
        "ai": ai,
        "presidio": pii_ok,
    }
