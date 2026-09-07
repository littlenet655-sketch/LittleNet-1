import json
import os
import smtplib
import sys
import urllib.error
import urllib.request
from email.mime.text import MIMEText


def _send_via_resend(api_key, receiver, subject, body, from_email=None, from_name=None):
    """Deliver an HTML email using the Resend REST API."""
    from_name = from_name or os.getenv('RESEND_FROM_NAME') or 'LittleNet Safety'
    configured_from = from_email or os.getenv('RESEND_FROM_EMAIL')

    candidates = []
    if configured_from:
        candidates.append(f"{from_name} <{configured_from}>")
    # Always include onboarding@resend.dev as fallback for unverified custom domains
    sandbox_from = f"{from_name} <onboarding@resend.dev>"
    if sandbox_from not in candidates:
        candidates.append(sandbox_from)

    last_error = None
    for from_header in candidates:
        payload = {
            "from": from_header,
            "to": [receiver],
            "subject": subject,
            "html": body,
        }
        req = urllib.request.Request(
            "https://api.resend.com/emails",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
                "User-Agent": "LittleNet/1.0",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                if resp.status in (200, 201):
                    return True
        except urllib.error.HTTPError as exc:
            err_body = exc.read().decode("utf-8", errors="replace")
            last_error = f"HTTP {exc.code}: {err_body}"
            # If domain is not verified, retry with sandbox from address
            if exc.code == 400 and ("not verified" in err_body.lower() or "domain" in err_body.lower()):
                if from_header != candidates[-1]:
                    continue
            if exc.code == 403 and "only send testing emails" in err_body:
                print(f"[RESEND SANDBOX RESTRICTION] {err_body.strip()}")
                break
            break
        except Exception as exc:
            last_error = str(exc)
            break

    safe_subject = str(subject).encode('ascii', errors='replace').decode('ascii')
    print(f"[RESEND WARNING] Delivery of '{safe_subject}' to {receiver} failed: {last_error}")
    return False


def _send_via_smtp(receiver, subject, body):
    """Deliver an HTML email using standard SMTP relay."""
    host = os.getenv('SMTP_HOST') or 'smtp.gmail.com'
    try:
        port = int(os.getenv('SMTP_PORT', '587'))
    except (ValueError, TypeError):
        port = 587
    email = os.getenv('SMTP_USER') or os.getenv('MAIL_EMAIL')
    password = os.getenv('SMTP_PASSWORD') or os.getenv('MAIL_PASSWORD')
    use_tls = os.getenv('SMTP_USE_TLS', 'true').lower() in ('1', 'true', 'yes')

    if not email or not password:
        return False
    try:
        msg = MIMEText(body, 'html', 'utf-8')
        msg['Subject'] = subject
        msg['From'] = f"LittleNet Safety <{email}>"
        msg['To'] = receiver
        with smtplib.SMTP(host, port, timeout=15) as s:
            if use_tls:
                s.starttls()
            s.login(email, password)
            s.send_message(msg)
        return True
    except Exception as exc:
        safe_exc = str(exc).encode('ascii', errors='replace').decode('ascii')
        print(f'[SMTP WARNING] {safe_exc}')
        return False


def send_email(receiver, subject, body):
    """Send transactional email via Resend API (primary) or SMTP (secondary)."""
    resend_key = os.getenv('RESEND_API_KEY')
    if resend_key:
        if _send_via_resend(resend_key, receiver, subject, body):
            return True

    if _send_via_smtp(receiver, subject, body):
        return True

    safe_subject = str(subject).encode('ascii', errors='replace').decode('ascii')
    print(f'[MAIL-DEMO] {safe_subject} -> {receiver}')
    return False

