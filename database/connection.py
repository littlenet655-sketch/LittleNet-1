import os
from dotenv import load_dotenv
load_dotenv()


def get_db_connection():
    try:
        import psycopg2
        from psycopg2.extras import RealDictCursor
    except ImportError as exc:
        raise RuntimeError('psycopg2 is required. Install requirements-core.txt') from exc
    url=os.getenv('DATABASE_URL','postgresql://postgres:littlenet@localhost:5432/safeconnect_db')
    # Passing the DSN through intact preserves hosted options such as sslmode.
    return psycopg2.connect(url,cursor_factory=RealDictCursor)


def fetch_one(sql,params=()):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:cur.execute(sql,params);return cur.fetchone()
    finally:conn.close()


def fetch_all(sql,params=()):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:cur.execute(sql,params);return cur.fetchall()
    finally:conn.close()


def execute(sql,params=(),returning=False):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql,params);row=cur.fetchone() if returning else None
        conn.commit();return row
    except Exception:
        conn.rollback();raise
    finally:conn.close()
