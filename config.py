import os
import secrets
from datetime import timedelta
from dotenv import load_dotenv
load_dotenv()


_BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:5000").strip() or "http://127.0.0.1:5000"
_SECRET_FROM_ENV = os.getenv("SECRET_KEY", "").strip()
_DATABASE_FROM_ENV = os.getenv("DATABASE_URL", "").strip()

# Local source/tests may import the Flask app without a .env file. Use an
# ephemeral, process-local signing key there rather than a public hard-coded
# value. Public HTTPS deployments must provide durable secrets explicitly.
if _BASE_URL.startswith("https://") and not _SECRET_FROM_ENV:
    raise RuntimeError("SECRET_KEY is required for HTTPS/production deployments")
if _BASE_URL.startswith("https://") and not _DATABASE_FROM_ENV:
    raise RuntimeError("DATABASE_URL is required for HTTPS/production deployments")


class Config:
    SECRET_KEY = _SECRET_FROM_ENV or secrets.token_urlsafe(48)
    DATABASE_URL = _DATABASE_FROM_ENV
    BASE_URL = _BASE_URL
    MAX_CONTENT_LENGTH = 100 * 1024 * 1024
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.getenv("COOKIE_SECURE", "1" if BASE_URL.startswith("https://") else "0") == "1"
    WTF_CSRF_SSL_STRICT = False
    WTF_CSRF_TIME_LIMIT = None  # Valid for the life of the session
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    ADULT_HARD_BLOCK_THRESHOLD = min(float(os.getenv("ADULT_HARD_BLOCK_THRESHOLD", "0.40")), 0.40)
    REEL_MAX_SECONDS = int(os.getenv("REEL_MAX_SECONDS", "180"))
    STORY_MAX_SECONDS = int(os.getenv("STORY_MAX_SECONDS", "60"))
    VIDEO_MAX_SECONDS = int(os.getenv("VIDEO_MAX_SECONDS", "600"))
    MESSAGE_MEDIA_MAX_MB = int(os.getenv("MESSAGE_MEDIA_MAX_MB", "40"))
    APP_TIMEZONE = os.getenv("APP_TIMEZONE", "Asia/Kolkata")

    AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "").strip()
    AI_SHARED_SECRET = os.getenv("AI_SHARED_SECRET", "").strip()
