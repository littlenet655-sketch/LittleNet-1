from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def test_live_release_preflight_runs_before_gpu_model_warmup():
    workflow = (ROOT / ".github/workflows/deploy-modal.yml").read_text(encoding="utf-8")
    preflight = "Run DB, AI, Presidio, liveness, mail, R2 and BASE_URL preflight"
    warmup = "Warm and validate every locked-scope AI model"
    assert preflight in workflow
    assert warmup in workflow
    assert workflow.index(preflight) < workflow.index(warmup)


def test_modal_docs_name_every_live_web_dependency_key():
    docs = (ROOT / "MODAL_DEPLOYMENT.md").read_text(encoding="utf-8")
    required = [
        "MODAL_TOKEN_ID",
        "MODAL_TOKEN_SECRET",
        "DATABASE_URL",
        "SECRET_KEY",
        "AI_SERVICE_URL",
        "AI_SHARED_SECRET",
        "BASE_URL",
        "R2_ACCOUNT_ID",
        "R2_ACCESS_KEY_ID",
        "R2_SECRET_ACCESS_KEY",
        "R2_BUCKET",
        "SMTP_USER",
        "SMTP_PASSWORD",
        "MAIL_EMAIL",
        "MAIL_PASSWORD",
    ]
    for key in required:
        assert key in docs, key
