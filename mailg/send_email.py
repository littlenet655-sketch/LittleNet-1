import os, smtplib
from email.mime.text import MIMEText

def send_email(receiver,subject,body):
    email=os.getenv('MAIL_EMAIL'); password=os.getenv('MAIL_PASSWORD')
    if not email or not password:
        print(f'[MAIL-DEMO] {subject} -> {receiver}')
        return False
    try:
        msg=MIMEText(body,'html'); msg['Subject']=subject; msg['From']=email; msg['To']=receiver
        with smtplib.SMTP('smtp.gmail.com',587,timeout=15) as s:
            s.starttls(); s.login(email,password); s.send_message(msg)
        return True
    except Exception as exc:
        print('[MAIL WARNING]',exc); return False
