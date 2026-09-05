import os
from unittest.mock import MagicMock, patch
from mailg.send_email import send_email

def test_send_email_demo_fallback_when_credentials_absent():
    with patch.dict(os.environ, {}, clear=True):
        res = send_email('test@example.com', 'Test Subject', '<h1>Hello</h1>')
        assert res is False

def test_send_email_smtp_delivery_with_credentials():
    mock_smtp_instance = MagicMock()
    with patch.dict(os.environ, {
        'SMTP_HOST': 'smtp.custom.org',
        'SMTP_PORT': '587',
        'SMTP_USER': 'notifications@littlenet.safe',
        'SMTP_PASSWORD': 'supersecretpassword',
        'SMTP_USE_TLS': 'true'
    }):
        with patch('smtplib.SMTP', return_value=mock_smtp_instance) as mock_smtp_cls:
            mock_smtp_instance.__enter__.return_value = mock_smtp_instance
            res = send_email('parent@example.com', 'Alert: Content Flagged', '<p>Safety notice</p>')
            assert res is True
            mock_smtp_cls.assert_called_once_with('smtp.custom.org', 587, timeout=15)
            mock_smtp_instance.starttls.assert_called_once()
            mock_smtp_instance.login.assert_called_once_with('notifications@littlenet.safe', 'supersecretpassword')
            assert mock_smtp_instance.send_message.called
            sent_msg = mock_smtp_instance.send_message.call_args[0][0]
            assert sent_msg['Subject'] == 'Alert: Content Flagged'
            assert 'notifications@littlenet.safe' in sent_msg['From']
            assert sent_msg['To'] == 'parent@example.com'
