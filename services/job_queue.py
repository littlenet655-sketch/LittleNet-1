"""Background job queue abstraction for LittleNet asynchronous media processing.

Production uses Modal's own async Function.spawn() path. LocalJobQueue exists only
for development/test execution. QStash has been retired from the supported
architecture and must not be used as a production fallback.
"""
from __future__ import annotations

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
    """Execute jobs locally for development/tests only."""

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
                if job_type != "media_processing":
                    raise RuntimeError(f"Unsupported local job type: {job_type}")
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
    """Optional compatibility provider for older deployments using Upstash QStash."""

    def __init__(self, token: str, endpoint_url: str, base_url: str | None = None):
        self.token = token
        self.endpoint_url = endpoint_url
        self.base_url = (base_url or os.getenv("QSTASH_URL") or "https://qstash.upstash.io").rstrip("/")

    def enqueue(self, job_type: str, payload: dict[str, Any], deduplication_id: str | None = None) -> str:
        import json
        import requests

        headers = {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"}
        if deduplication_id:
            headers["Upstash-Deduplication-Id"] = deduplication_id
        ai_secret = (os.getenv("AI_SHARED_SECRET") or "").strip()
        if ai_secret:
            headers["Upstash-Forward-X-LittleNet-AI-Key"] = ai_secret

        qstash_url = f"{self.base_url}/v2/publish/{self.endpoint_url}"
        data = {"job_type": job_type, "payload": payload}
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


class ModalJobQueue(JobQueue):
    """Production provider: asynchronously spawn the deployed Modal media worker."""

    def __init__(self, app_name: str = "littlenet-web", function_name: str = "process_media_job_background"):
        self.app_name = app_name
        self.function_name = function_name

    def enqueue(self, job_type: str, payload: dict[str, Any], deduplication_id: str | None = None) -> str:
        if job_type != "media_processing":
            raise RuntimeError(f"Unsupported Modal job type: {job_type}")
        try:
            import modal

            fn = modal.Function.from_name(self.app_name, self.function_name)
            call = fn.spawn(
                int(payload["post_id"]),
                int(payload["child_id"]),
                str(payload["object_key"]),
                str(payload.get("kind", "post")),
            )
            return str(call.object_id)
        except Exception as exc:
            logger.exception("Failed to spawn Modal background media job")
            raise RuntimeError(f"Modal background job spawn failed: {type(exc).__name__}: {exc}") from None


def validate_job_queue_config(is_production: bool | None = None) -> str:
    """Validate queue configuration and fail closed in production.

    Production supports only the Modal-native queue. Local execution is permitted
    only in development/test environments. A stale or unknown provider never
    silently downgrades production to an in-process thread.
    """
    from config import Config

    if is_production is None:
        is_production = Config._PRODUCTION and not (
            bool(os.getenv("PYTEST_CURRENT_TEST"))
            and os.getenv("LITTLENET_FORCE_PROD_QUEUE") != "1"
        )

    provider = (os.getenv("JOB_QUEUE_PROVIDER") or "").strip().lower()

    if is_production:
        if provider and provider != "modal":
            raise RuntimeError(
                f"Production configuration error: JOB_QUEUE_PROVIDER must be 'modal', got '{provider}'"
            )
        return "modal"

    if provider and provider not in {"local", "modal"}:
        raise RuntimeError(
            f"Invalid configuration: JOB_QUEUE_PROVIDER='{provider}'; must be 'local' or 'modal'"
        )

    return provider or "local"


def get_job_queue() -> JobQueue:
    """Return the configured queue provider."""
    provider = validate_job_queue_config()
    if provider == "modal":
        return ModalJobQueue()
    return LocalJobQueue(run_sync=os.getenv("LITTLENET_SYNC_JOBS") == "1")


def enqueue_media_job(post_id: int, child_id: int, object_key: str, kind: str) -> str:
    """Enqueue an asynchronous media-processing job."""
    queue = get_job_queue()
    payload = {
        "post_id": post_id,
        "child_id": child_id,
        "object_key": object_key,
        "kind": kind,
    }
    dedup_id = f"proc_post_{post_id}"
    return queue.enqueue("media_processing", payload, deduplication_id=dedup_id)
