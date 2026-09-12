"""Background job queue abstraction for LittleNet asynchronous media processing.

Supports QStash for production background dispatch to Modal, and LocalJobQueue
for development and test execution without external cloud dependencies.
"""
from __future__ import annotations

import json
import logging
import os
import threading
from abc import ABC, abstractmethod
from typing import Any

logger = logging.getLogger(__name__)


class JobQueue(ABC):
    @abstractmethod
    def enqueue(self, job_type: str, payload: dict[str, Any], deduplication_id: str | None = None) -> str:
        """Enqueue a job with small metadata payload. Returns job ID."""
        pass


class LocalJobQueue(JobQueue):
    """Executes jobs locally in background threads or synchronously for testing."""

    def __init__(self, run_sync: bool = False):
        self.run_sync = run_sync
        self._processed_dedup_keys: set[str] = set()

    def enqueue(self, job_type: str, payload: dict[str, Any], deduplication_id: str | None = None) -> str:
        if deduplication_id and deduplication_id in self._processed_dedup_keys:
            logger.info("LocalJobQueue: deduplicating job %s", deduplication_id)
            return deduplication_id

        job_id = deduplication_id or f"local_{payload.get('post_id')}_{os.urandom(4).hex()}"
        if deduplication_id:
            self._processed_dedup_keys.add(deduplication_id)

        def runner():
            try:
                if job_type == "media_processing":
                    from services.media_processor import process_media_job

                    process_media_job(
                        post_id=payload["post_id"],
                        child_id=payload["child_id"],
                        object_key=payload["object_key"],
                        kind=payload.get("kind", "post"),
                    )
            except Exception as exc:
                logger.exception("LocalJobQueue task error: %s", exc)

        if self.run_sync or os.getenv("LITTLENET_SYNC_JOBS") == "1":
            runner()
        else:
            t = threading.Thread(target=runner, daemon=True, name=f"job_{job_id}")
            t.start()

        return job_id


class QStashJobQueue(JobQueue):
    """Production provider: dispatches job to Modal worker via Upstash QStash."""

    def __init__(self, token: str, endpoint_url: str, base_url: str | None = None):
        self.token = token
        self.endpoint_url = endpoint_url
        self.base_url = (base_url or os.getenv("QSTASH_URL") or "https://qstash.upstash.io").rstrip("/")

    def enqueue(self, job_type: str, payload: dict[str, Any], deduplication_id: str | None = None) -> str:
        import requests

        headers = {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }
        if deduplication_id:
            headers["Upstash-Deduplication-Id"] = deduplication_id

        # Defense-in-depth: forward AI_SHARED_SECRET to Modal receiver via Upstash-Forward header
        ai_secret = (os.getenv("AI_SHARED_SECRET") or "").strip()
        if ai_secret:
            headers["Upstash-Forward-X-LittleNet-AI-Key"] = ai_secret

        # Target endpoint (Modal webhook or LittleNet worker)
        qstash_url = f"{self.base_url}/v2/publish/{self.endpoint_url}"
        data = {
            "job_type": job_type,
            "payload": payload,
        }
        try:
            resp = requests.post(qstash_url, headers=headers, data=json.dumps(data), timeout=10)
            resp.raise_for_status()
            return resp.json().get("messageId", deduplication_id or "qstash_dispatched")
        except Exception as exc:
            err_msg = str(exc).replace(self.token, "[REDACTED]")
            if ai_secret:
                err_msg = err_msg.replace(ai_secret, "[REDACTED]")
            logger.error("Failed to publish job to QStash at %s: %s", qstash_url, err_msg)
            raise RuntimeError(f"QStash publish failed: {err_msg}") from None


def validate_job_queue_config(is_production: bool | None = None) -> str:
    """Validate queue provider configuration and enforce production fail-closed rules."""
    from config import Config

    if is_production is None:
        # In test runners, enforce production only when explicitly testing production or forced
        is_production = Config._PRODUCTION and not (
            bool(os.getenv("PYTEST_CURRENT_TEST"))
            and os.getenv("LITTLENET_FORCE_PROD_QUEUE") != "1"
        )

    provider = (os.getenv("JOB_QUEUE_PROVIDER") or "").strip().lower()

    if is_production:
        if not provider:
            raise RuntimeError(
                "Production configuration error: JOB_QUEUE_PROVIDER is required and must be 'qstash'"
            )
        if provider != "qstash":
            raise RuntimeError(
                f"Production configuration error: LocalJobQueue is forbidden in production; JOB_QUEUE_PROVIDER must be 'qstash', got '{provider}'"
            )
        token = (os.getenv("QSTASH_TOKEN") or "").strip()
        if not token:
            raise RuntimeError(
                "Production configuration error: QSTASH_TOKEN is required when JOB_QUEUE_PROVIDER is 'qstash'"
            )
        endpoint = (os.getenv("QSTASH_MODAL_ENDPOINT") or "").strip()
        if not endpoint:
            raise RuntimeError(
                "Production configuration error: QSTASH_MODAL_ENDPOINT is required when JOB_QUEUE_PROVIDER is 'qstash'"
            )
        return "qstash"

    # Development / Test rules
    if provider and provider not in ("local", "qstash"):
        raise RuntimeError(
            f"Invalid configuration: JOB_QUEUE_PROVIDER='{provider}'; must be 'local' or 'qstash'"
        )

    if provider == "qstash":
        token = (os.getenv("QSTASH_TOKEN") or "").strip()
        endpoint = (os.getenv("QSTASH_MODAL_ENDPOINT") or "").strip()
        if not token or not endpoint:
            raise RuntimeError(
                "Configuration error: QSTASH_TOKEN and QSTASH_MODAL_ENDPOINT are required when JOB_QUEUE_PROVIDER is 'qstash'"
            )
        return "qstash"

    return "local"


def get_job_queue() -> JobQueue:
    """Return configured queue provider. Enforces production fail-closed rules."""
    provider = validate_job_queue_config()
    if provider == "qstash":
        token = os.environ["QSTASH_TOKEN"].strip()
        endpoint = os.environ["QSTASH_MODAL_ENDPOINT"].strip()
        base_url = (os.getenv("QSTASH_URL") or "").strip() or None
        return QStashJobQueue(token, endpoint, base_url=base_url)

    return LocalJobQueue(run_sync=os.getenv("LITTLENET_SYNC_JOBS") == "1")


def enqueue_media_job(post_id: int, child_id: int, object_key: str, kind: str) -> str:
    """Helper to enqueue an asynchronous media processing job."""
    queue = get_job_queue()
    payload = {
        "post_id": post_id,
        "child_id": child_id,
        "object_key": object_key,
        "kind": kind,
    }
    dedup_id = f"proc_post_{post_id}"
    return queue.enqueue("media_processing", payload, deduplication_id=dedup_id)
