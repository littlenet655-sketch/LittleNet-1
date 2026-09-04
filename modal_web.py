"""Optional Modal deployment for LittleNet's Flask/Jinja web application.

This keeps the *web compute* on Modal as well as the AI service. PostgreSQL
remains external (Railway/Neon/Supabase/etc.), because a Modal Volume is not a
relational database.

Typical sequence:
    modal deploy modal_ai.py
    # create littlenet-web-secrets with DATABASE_URL/SECRET_KEY/AI_* values
    modal deploy modal_web.py
    modal run modal_web.py::init_database

Uploads are mounted on a persistent Modal Volume. This web function is capped at
one container to avoid concurrent write semantics on that Volume in the college
project build.
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
    .pip_install_from_requirements(str(ROOT / "requirements-core.txt"))
    .workdir("/root/littlenet")
    .env(
        {
            "COOKIE_SECURE": "1",
            "LITTLENET_DEVICE": "cpu",
        }
    )
    .add_local_dir(
        str(ROOT),
        remote_path="/root/littlenet",
        ignore=[
            ".git/**",
            ".pytest_cache/**",
            "**/__pycache__/**",
            "uploads/**",
            "android/.gradle/**",
            "android/**/build/**",
            "*.zip",
            ".env",
        ],
        copy=True,
    )
)


@app.function(
    image=web_image,
    cpu=1.0,
    memory=1536,
    secrets=[web_secret],
    volumes={"/root/littlenet/uploads": uploads},
    timeout=300,
    startup_timeout=120,
    scaledown_window=300,
    min_containers=0,
    max_containers=1,
)
@modal.concurrent(max_inputs=20, target_inputs=10)
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
        # DB state is already durable in PostgreSQL. Only filesystem changes need
        # a Volume commit. One container is used so there are no competing web
        # writers to the same Volume in this college-project deployment.
        if request.method in {"POST", "PUT", "PATCH", "DELETE"} and request.files:
            try:
                uploads.commit()
            except Exception:
                # A failed commit must not turn an already-completed DB response
                # into a 500. The next write/readiness check will surface storage
                # trouble; moderation itself remains fail-closed independently.
                flask_app.logger.exception("Modal uploads Volume commit failed")
        return response

    return flask_app


@app.function(image=web_image, secrets=[web_secret], timeout=300)
def init_database():
    """Create/upgrade schema and idempotent seed data on the external Postgres DB."""
    os.chdir("/root/littlenet")
    subprocess.run(["python", "tools/init_db.py"], check=True)
    return {"ok": True}


@app.function(image=web_image, secrets=[web_secret], timeout=120)
def web_preflight():
    """Verify database connectivity and remote AI readiness from Modal's network."""
    os.chdir("/root/littlenet")
    from database.connection import fetch_one
    from safety.remote_client import health

    db = fetch_one("SELECT 1 ok")
    ai = health()
    return {"ok": bool(db and db["ok"] == 1 and ai.get("ok")), "database": True, "ai": ai}
