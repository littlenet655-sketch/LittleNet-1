"""QStash inbound signature verification for LittleNet background job receivers.

Verifies the `Upstash-Signature` JWT header using the official Upstash QStash
Python SDK Receiver, enforcing official claim semantics:
- iss == "Upstash"
- sub == destination URL
- exp not expired
- nbf already valid (clock tolerance applied)
- body claim == SHA-256 base64url hash of raw request body
- Current key with rotation fallback to next key

Never logs or exposes secret signing keys or sensitive tokens.
"""
from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)


def verify_qstash_signature(
    body: bytes | str,
    signature: str,
    current_key: str,
    next_key: str | None = None,
    url: str | None = None,
    tolerance: int = 900,
) -> bool:
    """Verify an Upstash QStash request signature using the official Receiver.

    Supports current and next signing keys for seamless key rotation.
    Fails closed on missing/invalid signature, expired token, mismatched URL (sub),
    or body hash mismatch.
    """
    if not signature or not current_key:
        return False

    c_key = current_key.strip()
    n_key = (next_key or current_key).strip()
    if not c_key:
        return False

    raw_str = body.decode("utf-8", errors="replace") if isinstance(body, bytes) else str(body)

    try:
        from qstash import Receiver
        from qstash.errors import SignatureError

        receiver = Receiver(current_signing_key=c_key, next_signing_key=n_key)
        receiver.verify(
            body=raw_str,
            signature=signature.strip(),
            url=url.strip() if url else None,
            clock_tolerance=tolerance,
        )
        return True
    except SignatureError:
        return False
    except Exception:
        return False
