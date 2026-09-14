import json
import os
import urllib.error
import urllib.request


def _resend_from_email() -> str:
    """Return the configured LittleNet-owned Resend sender address."""
    return (
        os.getenv('LITTLENET_RESEND_FROM_EMAIL')
        or os.getenv('RESEND_FROM_EMAIL')
        or ''
    ).strip()


def _is_sandbox_sender(from_email: str) -> bool:
    return not from_email or from_email.lower().endswith('@resend.dev')


def _send_via_resend(api_key, receiver, subject, body, from_email=None, from_name=None):
    """Deliver an HTML email through Resend without provider fallbacks.

    LittleNet uses this path for parent OTPs and safety notifications. A
    sandbox sender, SMTP fallback, or demo success would make an OTP appear
    deliverable when it is not, so every failure is explicit and fail-closed.
    """
    configured_from = (from_email or _resend_from_email()).strip()
    if _is_sandbox_sender(configured_from):
        print('[RESEND CONFIG ERROR] RESEND_FROM_EMAIL must be a verified LittleNet sender.')
        return False

    sender_name = from_name or os.getenv('RESEND_FROM_NAME') or 'LittleNet Safety'
    payload = {
        'from': f'{sender_name} <{configured_from}>',
        'to': [receiver],
        'subject': subject,
        'html': body,
    }
    request = urllib.request.Request(
        'https://api.resend.com/emails',
        data=json.dumps(payload).encode('utf-8'),
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json',
            'User-Agent': 'LittleNet/1.0',
        },
        method='POST',
    )
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            if response.status in (200, 201):
                return True
            print(f'[RESEND WARNING] Unexpected status {response.status}.')
    except urllib.error.HTTPError as exc:
        error_body = exc.read().decode('utf-8', errors='replace')
        safe_subject = str(subject).encode('ascii', errors='replace').decode('ascii')
        print(f'[RESEND WARNING] Delivery of {safe_subject!r} failed: HTTP {exc.code}: {error_body}')
    except Exception as exc:
        safe_subject = str(subject).encode('ascii', errors='replace').decode('ascii')
        safe_error = str(exc).encode('ascii', errors='replace').decode('ascii')
        print(f'[RESEND WARNING] Delivery of {safe_subject!r} failed: {safe_error}')
    return False


def get_mail_status():
    """Report whether the strict Resend production contract is configured."""
    resend_key = bool(os.getenv('RESEND_API_KEY'))
    from_email = _resend_from_email().lower()
    sender_is_production = bool(from_email) and not _is_sandbox_sender(from_email)
    configured = resend_key and sender_is_production
    return {
        'ok': configured,
        'configured': configured,
        'provider': 'resend' if resend_key else None,
        'mail_mode': 'resend_verified' if configured else 'not_configured',
        'from_email': from_email or None,
        'is_production_ready': configured,
    }


def send_email(receiver, subject, body):
    """Send transactional email through the verified Resend production sender."""
    resend_key = os.getenv('RESEND_API_KEY')
    if not resend_key:
        print('[RESEND CONFIG ERROR] RESEND_API_KEY is not configured.')
        return False
    return _send_via_resend(resend_key, receiver, subject, body)
