import os
import urllib.error
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


def test_send_email_resend_delivery_success():
    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.read.return_value = b'{"id": "msg_12345"}'
    mock_resp.__enter__.return_value = mock_resp

    with patch.dict(os.environ, {
        'RESEND_API_KEY': 're_test_key_123',
        'RESEND_FROM_EMAIL': 'no-reply@devpluse.in',
        'RESEND_FROM_NAME': 'LittleNet Safety',
    }, clear=True):
        with patch('urllib.request.urlopen', return_value=mock_resp) as mock_urlopen:
            res = send_email('parent@example.com', 'Your OTP Code', '<p>Code: 123456</p>')
            assert res is True
            assert mock_urlopen.called
            req = mock_urlopen.call_args[0][0]
            assert req.full_url == 'https://api.resend.com/emails'
            assert req.headers.get('Authorization') == 'Bearer re_test_key_123'
            import json
            payload = json.loads(req.data.decode('utf-8'))
            assert payload['to'] == ['parent@example.com']
            assert payload['subject'] == 'Your OTP Code'
            assert 'LittleNet Safety <no-reply@devpluse.in>' in payload['from']


def test_send_email_resend_unverified_domain_retries_with_sandbox():
    mock_resp_success = MagicMock()
    mock_resp_success.status = 200
    mock_resp_success.read.return_value = b'{"id": "msg_sandbox_123"}'
    mock_resp_success.__enter__.return_value = mock_resp_success

    import io
    err_stream = io.BytesIO(b'{"statusCode":400,"message":"The associated domain with your API key is not verified."}')
    http_err = urllib.error.HTTPError(
        url='https://api.resend.com/emails',
        code=400,
        msg='Bad Request',
        hdrs={},
        fp=err_stream,
    )

    with patch.dict(os.environ, {
        'RESEND_API_KEY': 're_test_key_123',
        'RESEND_FROM_EMAIL': 'no-reply@unverified.in',
        'RESEND_FROM_NAME': 'LittleNet Safety',
    }, clear=True):
        with patch('urllib.request.urlopen', side_effect=[http_err, mock_resp_success]) as mock_urlopen:
            res = send_email('littlenet655@gmail.com', 'Your OTP Code', '<p>Code: 999999</p>')
            assert res is True
            assert mock_urlopen.call_count == 2
            # Second call should use onboarding@resend.dev
            second_req = mock_urlopen.call_args_list[1][0][0]
            import json
            payload = json.loads(second_req.data.decode('utf-8'))
            assert 'onboarding@resend.dev' in payload['from']


