"""QStash inbound signature verification for LittleNet background job receivers.

Verifies the `Upstash-Signature` JWT header using current and next signing keys,
preventing arbitrary public requests from triggering asynchronous processing jobs.
"""
from __future__ import annotations

import base64
import hashlib
import time
from typing import Any

import jwt


def verify_qstash_signature(
    body: bytes | str,
    signature: str,
    current_key: str,
    next_key: str | None = None,
    url: str | None = None,
    tolerance: int = 900,
) -> bool:
    """Verify an Upstash QStash request signature.

    Supports current and next signing keys for key rotation.
    Fails closed on missing/invalid signature, expired token, or body hash mismatch.
    Never logs or exposes secret keys.
    """
    if not signature or not current_key:
        return False

    keys = [k.strip() for k in (current_key, next_key) if k and k.strip()]
    if not keys:
        return False

    raw_bytes = body.encode("utf-8") if isinstance(body, str) else body

    # Compute body hashes (QStash uses base64url or hex SHA-256)
    sha256_digest = hashlib.sha256(raw_bytes).digest()
    b64url_hash = base64.urlsafe_b64encode(sha256_digest).decode("utf-8").rstrip("=")
    hex_hash = hashlib.sha256(raw_bytes).hexdigest()

    for key in keys:
        try:
            claims: dict[str, Any] = jwt.decode(
                signature,
                key,
                algorithms=["HS256"],
                options={"verify_exp": True, "verify_nbf": False},
                leeway=tolerance,
            )

            # Issuer must be Upstash
            if claims.get("iss") != "Upstash":
                continue

            # Optional URL/subject claim verification
            if url and claims.get("sub"):
                target = claims["sub"].rstrip("/")
                incoming = url.rstrip("/")
                if target != incoming:
                    continue

            # Body hash verification: if present, must match computed digest
            body_claim = claims.get("body")
            if body_claim and body_claim not in (b64url_hash, hex_hash):
                continue

            return True
        except Exception:
            continue

    return False
