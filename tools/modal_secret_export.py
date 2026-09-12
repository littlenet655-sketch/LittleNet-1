"""One-shot helper to export LittleNet Modal secret values to local dotenv files.

Run ONLY while the old Modal profile is active:
    modal run tools/modal_secret_export.py --output-dir <local-dir>

The remote functions mount each named Modal secret and return only a strict
allow-list of LittleNet keys. The local entrypoint writes those values to
separate dotenv files without printing secret values to stdout.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import modal

app = modal.App("littlenet-secret-export-temp")

AI_KEYS = (
    "AI_SHARED_SECRET",
)

WEB_KEYS = (
    "DATABASE_URL",
    "SECRET_KEY",
    "BASE_URL",
    "COOKIE_SECURE",
    "AI_SERVICE_URL",
    "AI_SHARED_SECRET",
    "AI_REQUEST_TIMEOUT",
    "JOB_QUEUE_PROVIDER",
    "QSTASH_TOKEN",
    "QSTASH_CURRENT_SIGNING_KEY",
    "QSTASH_NEXT_SIGNING_KEY",
    "QSTASH_MODAL_ENDPOINT",
    "QSTASH_URL",
    "APP_TIMEZONE",
    "LITTLENET_SYNC_JOBS",
    "TURNSTILE_SITE_KEY",
    "TURNSTILE_SECRET_KEY",
    "K2_HORIZON_ENABLED",
    "K2_HORIZON_BASE_URL",
    "K2_HORIZON_API_KEY",
    "K2_HORIZON_MODEL",
    "K2_CONNECT_TIMEOUT",
    "K2_READ_TIMEOUT",
    "K2_MAX_RETRIES",
    "K2_CIRCUIT_BREAKER_THRESHOLD",
    "K2_CIRCUIT_BREAKER_RESET_SECONDS",
    "MAIL_EMAIL",
    "MAIL_PASSWORD",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_USER",
    "SMTP_PASSWORD",
    "SMTP_USE_TLS",
)

R2_KEYS = (
    "R2_ACCOUNT_ID",
    "R2_ACCESS_KEY_ID",
    "R2_SECRET_ACCESS_KEY",
    "R2_BUCKET",
    "R2_SIGNED_URL_TTL",
)

EMAIL_KEYS = (
    "RESEND_API_KEY",
    "RESEND_FROM_EMAIL",
    "RESEND_FROM_NAME",
    "RESEND_DOMAIN_VERIFIED",
    "MAIL_EMAIL",
    "MAIL_PASSWORD",
    "SMTP_HOST",
    "SMTP_PORT",
    "SMTP_USER",
    "SMTP_PASSWORD",
    "SMTP_USE_TLS",
)


def _read(keys: tuple[str, ...]) -> dict[str, str]:
    return {key: os.environ[key] for key in keys if os.environ.get(key) not in (None, "")}


@app.function(secrets=[modal.Secret.from_name("littlenet-ai-secrets")])
def read_ai() -> dict[str, str]:
    return _read(AI_KEYS)


@app.function(secrets=[modal.Secret.from_name("littlenet-web-secrets")])
def read_web() -> dict[str, str]:
    return _read(WEB_KEYS)


@app.function(secrets=[modal.Secret.from_name("littlenet-r2")])
def read_r2() -> dict[str, str]:
    return _read(R2_KEYS)


@app.function(secrets=[modal.Secret.from_name("littlenet-email")])
def read_email() -> dict[str, str]:
    return _read(EMAIL_KEYS)


def _dotenv_text(values: dict[str, str]) -> str:
    # JSON string quoting is accepted by dotenv parsers and safely escapes
    # spaces, quotes, backslashes and embedded newlines.
    return "".join(f"{key}={json.dumps(value, ensure_ascii=False)}\n" for key, value in sorted(values.items()))


@app.local_entrypoint()
def main(output_dir: str):
    out = Path(output_dir).expanduser().resolve()
    out.mkdir(parents=True, exist_ok=True)

    groups = {
        "littlenet-ai-secrets.env": read_ai.remote(),
        "littlenet-web-secrets.env": read_web.remote(),
        "littlenet-r2.env": read_r2.remote(),
        "littlenet-email.env": read_email.remote(),
    }

    required = {
        "littlenet-ai-secrets.env": {"AI_SHARED_SECRET"},
        "littlenet-web-secrets.env": {"DATABASE_URL", "SECRET_KEY", "AI_SERVICE_URL", "AI_SHARED_SECRET"},
        "littlenet-r2.env": {"R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET"},
    }

    for filename, values in groups.items():
        missing = sorted(required.get(filename, set()) - set(values))
        if missing:
            raise RuntimeError(f"{filename}: missing required key(s): {', '.join(missing)}")
        path = out / filename
        path.write_text(_dotenv_text(values), encoding="utf-8")
        print(f"Exported {filename}: {len(values)} key(s)")

    print(f"Secret export complete: {out}")
