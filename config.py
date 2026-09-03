import os
from datetime import timedelta
from dotenv import load_dotenv
load_dotenv()

class Config:
    SECRET_KEY = os.getenv("SECRET_KEY", "change-me-before-demo")
    DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://postgres:littlenet@localhost:5432/safeconnect_db")
    BASE_URL = os.getenv("BASE_URL", "http://127.0.0.1:5000")
    MAX_CONTENT_LENGTH = 100 * 1024 * 1024
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SAMESITE = "Lax"
    SESSION_COOKIE_SECURE = os.getenv("COOKIE_SECURE", "1" if BASE_URL.startswith("https://") else "0") == "1"
    PERMANENT_SESSION_LIFETIME = timedelta(hours=8)
    ADULT_HARD_BLOCK_THRESHOLD = min(float(os.getenv("ADULT_HARD_BLOCK_THRESHOLD", "0.40")), 0.40)
    REEL_MAX_SECONDS = int(os.getenv("REEL_MAX_SECONDS", "180"))
    STORY_MAX_SECONDS = int(os.getenv("STORY_MAX_SECONDS", "60"))
    VIDEO_MAX_SECONDS = int(os.getenv("VIDEO_MAX_SECONDS", "600"))
    MESSAGE_MEDIA_MAX_MB = int(os.getenv("MESSAGE_MEDIA_MAX_MB", "40"))
    APP_TIMEZONE = os.getenv("APP_TIMEZONE", "Asia/Kolkata")

    AI_SERVICE_URL = os.getenv("AI_SERVICE_URL", "").strip()
    AI_SHARED_SECRET = os.getenv("AI_SHARED_SECRET", "").strip()
