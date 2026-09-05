import os
import threading
from dotenv import load_dotenv
load_dotenv()

_pool = None
_pool_lock = threading.Lock()


def _get_pool():
    global _pool
    if _pool is None or _pool.closed:
        with _pool_lock:
            if _pool is None or _pool.closed:
                try:
                    import psycopg2
                    from psycopg2.pool import ThreadedConnectionPool
                    from psycopg2.extras import RealDictCursor
                except ImportError as exc:
                    raise RuntimeError('psycopg2 is required. Install requirements-core.txt') from exc
                url = os.getenv('DATABASE_URL', 'postgresql://postgres:littlenet@localhost:5432/safeconnect_db')
                _pool = ThreadedConnectionPool(1, 10, url, cursor_factory=RealDictCursor)
    return _pool


class PooledConnectionWrapper:
    """Wraps a pooled psycopg2 connection so conn.close() returns it to pool."""
    def __init__(self, pool, conn):
        self._pool = pool
        self._conn = conn
        self._closed = False

    def close(self):
        if not self._closed:
            self._closed = True
            if self._pool and not self._pool.closed:
                try:
                    if not self._conn.closed:
                        self._conn.rollback()
                    self._pool.putconn(self._conn)
                except Exception:
                    try:
                        self._pool.putconn(self._conn, close=True)
                    except Exception:
                        pass

    def __getattr__(self, name):
        return getattr(self._conn, name)

    def __enter__(self):
        return self._conn.__enter__()

    def __exit__(self, exc_type, exc_val, exc_tb):
        return self._conn.__exit__(exc_type, exc_val, exc_tb)


def get_db_connection():
    try:
        pool = _get_pool()
        raw_conn = pool.getconn()
        if raw_conn.closed:
            pool.putconn(raw_conn, close=True)
            raw_conn = pool.getconn()
        return PooledConnectionWrapper(pool, raw_conn)
    except Exception:
        # Fallback to direct connection if pool initialization or exhaustion occurs
        import psycopg2
        from psycopg2.extras import RealDictCursor
        url = os.getenv('DATABASE_URL', 'postgresql://postgres:littlenet@localhost:5432/safeconnect_db')
        return psycopg2.connect(url, cursor_factory=RealDictCursor)


def fetch_one(sql, params=()):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()
    finally:
        conn.close()


def fetch_all(sql, params=()):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchall()
    finally:
        conn.close()


def execute(sql, params=(), returning=False):
    conn = get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            row = cur.fetchone() if returning else None
        conn.commit()
        return row
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
