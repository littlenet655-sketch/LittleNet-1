import os, sys, smtplib
from email.mime.text import MIMEText

def send_email(receiver, subject, body):
    host = os.getenv('SMTP_HOST') or 'smtp.gmail.com'
    try:
        port = int(os.getenv('SMTP_PORT', '587'))
    except (ValueError, TypeError):
        port = 587
    email = os.getenv('SMTP_USER') or os.getenv('MAIL_EMAIL')
    password = os.getenv('SMTP_PASSWORD') or os.getenv('MAIL_PASSWORD')
    use_tls = os.getenv('SMTP_USE_TLS', 'true').lower() in ('1', 'true', 'yes')

    if not email or not password:
        safe_subject = str(subject).encode('ascii', errors='replace').decode('ascii')
        try:
            print(f'[MAIL-DEMO] {safe_subject} -> {receiver}')
        except Exception:
            pass
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
        try:
            print('[MAIL WARNING]', safe_exc)
        except Exception:
            pass
        return False
