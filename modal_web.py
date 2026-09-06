"""Optional Modal deployment for LittleNet's Flask/Jinja web application.

PostgreSQL remains external (Neon/etc.). Private media is stored in R2; the
legacy uploads volume remains only for compatibility with local/demo assets.
"""
from pathlib import Path
import os
import smtplib
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
    .apt_install("ffmpeg", "curl", "ca-certificates")
    .run_commands(
        "curl -fsSL -o /usr/local/bin/dbmate https://github.com/amacneil/dbmate/releases/download/v2.34.1/dbmate-linux-amd64",
        "chmod +x /usr/local/bin/dbmate",
        "dbmate --version",
    )
    .pip_install_from_requirements(str(ROOT / "requirements-safety.txt"))
    .run_commands("python -m spacy download en_core_web_sm")
    .workdir("/root/littlenet")
    .env(
        {
            "COOKIE_SECURE": "1",
            "LITTLENET_DEVICE": "cpu",
            "LITTLENET_ENABLE_PRESIDIO": "1",
            "LITTLENET_PRESIDIO_SPACY_MODEL": "en_core_web_sm",
            "DBMATE_MIGRATIONS_DIR": "/root/littlenet/db/migrations",
            "DBMATE_NO_DUMP_SCHEMA": "true",
            "DBMATE_STRICT": "true",
            "LITTLENET_DEPLOY_VERSION": "9",
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
    .run_commands("cd /root/littlenet && python tools/install_mediapipe_assets.py")
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
    """Bootstrap legacy schema safely, then apply all new dbmate migrations."""
    os.chdir("/root/littlenet")
    subprocess.run(["python", "tools/init_db.py"], check=True)
    subprocess.run(
        ["dbmate", "--strict", "--no-dump-schema", "--migrations-dir", "db/migrations", "up"],
        check=True,
        env=os.environ.copy(),
    )
    return {"ok": True, "migration_engine": "dbmate", "legacy_bootstrap": True}


@app.function(image=web_image, secrets=[web_secret], timeout=120)
def seed_quizzes():
    """Populate the idempotent age-banded quiz bank required by Kids Mode."""
    os.chdir("/root/littlenet")
    subprocess.run(["python", "tools/seed_quizzes.py"], check=True)
    return {"ok": True}


def _smtp_healthcheck():
    host = os.getenv("SMTP_HOST") or "smtp.gmail.com"
    try:
        port = int(os.getenv("SMTP_PORT", "587"))
    except (TypeError, ValueError):
        port = 587
    user = os.getenv("SMTP_USER") or os.getenv("MAIL_EMAIL")
    password = os.getenv("SMTP_PASSWORD") or os.getenv("MAIL_PASSWORD")
    use_tls = os.getenv("SMTP_USE_TLS", "true").lower() in {"1", "true", "yes"}
    if not user or not password:
        return {"ok": False, "configured": False, "host": host, "port": port}
    try:
        with smtplib.SMTP(host, port, timeout=15) as server:
            if use_tls:
                server.starttls()
            server.login(user, password)
        return {"ok": True, "configured": True, "host": host, "port": port}
    except Exception as exc:
        return {
            "ok": False,
            "configured": True,
            "host": host,
            "port": port,
            "error": f"{type(exc).__name__}: {exc}",
        }


@app.function(image=web_image, secrets=[web_secret], timeout=180)
def web_preflight():
    """Fail closed unless the complete live LittleNet dependency chain is usable."""
    os.chdir("/root/littlenet")
    from config import Config
    from database.connection import fetch_one
    from safety.remote_client import health
    from safety.presidio_adapter import analyze_pii
    from services.object_storage import healthcheck as r2_healthcheck

    db = fetch_one("SELECT 1 ok")
    schema = fetch_one("""
        SELECT
          to_regclass('public.users')::text AS users,
          to_regclass('public.child_profiles')::text AS child_profiles,
          to_regclass('public.posts')::text AS posts,
          to_regclass('public.comments')::text AS comments,
          to_regclass('public.followers')::text AS followers,
          to_regclass('public.quizzes')::text AS quizzes
    """) or {}
    required_tables = ("users", "child_profiles", "posts", "comments", "followers", "quizzes")
    schema_ok = all(schema.get(name) for name in required_tables)
    quiz_count = 0
    if schema_ok:
        quiz_row = fetch_one("SELECT COUNT(*)::int n FROM quizzes") or {}
        quiz_count = int(quiz_row.get("n") or 0)

    ai = health()
    pii = analyze_pii("test@example.com")
    pii_ok = bool(pii.get("available") and "EMAIL_ADDRESS" in pii.get("categories", []))
    vendor = Path("static/vendor/mediapipe")
    liveness_assets = all((vendor / name).exists() for name in (
        "vision_bundle.mjs", "face_landmarker.task", "wasm/vision_wasm_internal.wasm"
    ))

    base_url = str(Config.BASE_URL or "").rstrip("/")
    public_base_url = bool(
        base_url.startswith("https://")
        and "127.0.0.1" not in base_url
        and "localhost" not in base_url
        and "YOUR-LITTLENET-BACKEND" not in base_url
    )
    mail = _smtp_healthcheck()
    r2 = r2_healthcheck()

    report = {
        "database": bool(db and db["ok"] == 1),
        "database_schema": {"ok": schema_ok, "tables": schema, "quiz_count": quiz_count},
        "ai": ai,
        "presidio": pii_ok,
        "mediapipe_liveness_assets": liveness_assets,
        "base_url": {"ok": public_base_url, "value": base_url},
        "mail": mail,
        "r2": r2,
    }
    report["ok"] = bool(
        report["database"]
        and schema_ok
        and quiz_count > 0
        and ai.get("ok")
        and pii_ok
        and liveness_assets
        and public_base_url
        and mail.get("ok")
        and r2.get("ok")
    )
    return report


@app.local_entrypoint()
def main(init_db: bool = False, seed: bool = False, preflight: bool = False):
    """Release helper: migrate, seed mandatory quiz data, then validate dependencies."""
    if init_db:
        print("database", init_database.remote())
    if seed:
        print("quizzes", seed_quizzes.remote())
    if preflight:
        report = web_preflight.remote()
        print("preflight", report)
        if not report.get("ok"):
            raise RuntimeError(f"LittleNet web preflight failed: {report}")
