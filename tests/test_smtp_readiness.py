import io
import json
import os
import urllib.error
from unittest.mock import MagicMock, patch

from mailg.send_email import get_mail_status, send_email


def test_send_email_fails_closed_when_resend_credentials_are_absent():
    with patch.dict(os.environ, {}, clear=True):
        assert send_email('test@example.com', 'Test Subject', '<h1>Hello</h1>') is False
        assert get_mail_status()['is_production_ready'] is False


def test_send_email_resend_delivery_success():
    mock_resp = MagicMock()
    mock_resp.status = 200
    mock_resp.__enter__.return_value = mock_resp

    with patch.dict(os.environ, {
        'RESEND_API_KEY': 're_test_key_123',
        'RESEND_FROM_EMAIL': 'no-reply@littlenet.in',
        'RESEND_FROM_NAME': 'LittleNet Safety',
    }, clear=True):
        with patch('urllib.request.urlopen', return_value=mock_resp) as mock_urlopen:
            assert send_email('parent@example.com', 'Your OTP Code', '<p>Code: 123456</p>') is True
            req = mock_urlopen.call_args[0][0]
            assert req.full_url == 'https://api.resend.com/emails'
            assert req.headers.get('Authorization') == 'Bearer re_test_key_123'
            payload = json.loads(req.data.decode('utf-8'))
            assert payload['to'] == ['parent@example.com']
            assert payload['subject'] == 'Your OTP Code'
            assert payload['from'] == 'LittleNet Safety <no-reply@littlenet.in>'
            assert get_mail_status()['is_production_ready'] is True


def test_send_email_rejects_resend_sandbox_sender_without_fallback():
    with patch.dict(os.environ, {
        'RESEND_API_KEY': 're_test_key_123',
        'RESEND_FROM_EMAIL': 'onboarding@resend.dev',
    }, clear=True):
        with patch('urllib.request.urlopen') as mock_urlopen:
            assert send_email('parent@example.com', 'Your OTP Code', '<p>Code: 999999</p>') is False
            mock_urlopen.assert_not_called()
            assert get_mail_status()['is_production_ready'] is False


def test_send_email_resend_failure_does_not_fallback():
    err_stream = io.BytesIO(b'{"statusCode":400,"message":"The associated domain is not verified."}')
    http_err = urllib.error.HTTPError(
        url='https://api.resend.com/emails',
        code=400,
        msg='Bad Request',
        hdrs={},
        fp=err_stream,
    )
    with patch.dict(os.environ, {
        'RESEND_API_KEY': 're_test_key_123',
        'RESEND_FROM_EMAIL': 'no-reply@littlenet.in',
        'SMTP_USER': 'fallback@example.com',
        'SMTP_PASSWORD': 'should-not-be-used',
    }, clear=True):
        with patch('urllib.request.urlopen', side_effect=http_err) as mock_urlopen:
            assert send_email('parent@example.com', 'Your OTP Code', '<p>Code: 123456</p>') is False
            assert mock_urlopen.call_count == 1
