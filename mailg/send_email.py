import os, sys, smtplib
from email.mime.text import MIMEText

def send_email(receiver, subject, body):
    email = os.getenv('MAIL_EMAIL')
    password = os.getenv('MAIL_PASSWORD')
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
        with smtplib.SMTP('smtp.gmail.com', 587, timeout=15) as s:
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
