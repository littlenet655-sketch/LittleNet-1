import threading
from dotenv import load_dotenv
load_dotenv()

_pool = None
_pool_lock = threading.Lock()


def _database_url():
    # Config enforces explicit DATABASE_URL for HTTPS/production deployments.
    from config import Config
    return Config.DATABASE_URL


def _get_pool():
    global _pool
    if _pool is None or _pool.closed:
        with _pool_lock:
            if _pool is None or _pool.closed:
                try:
                    from psycopg2.pool import ThreadedConnectionPool
                    from psycopg2.extras import RealDictCursor
                except ImportError as exc:
                    raise RuntimeError('psycopg2 is required. Install requirements-core.txt') from exc
                _pool = ThreadedConnectionPool(2, 20, _database_url(), cursor_factory=RealDictCursor)
    return _pool


def _discard_connection(pool, conn):
    try:pool.putconn(conn, close=True)
    except Exception:
        try:conn.close()
        except Exception:pass


def _connection_is_usable(conn):
    if conn.closed:return False
    try:
        conn.rollback()
        with conn.cursor() as cur:cur.execute('SELECT 1')
        conn.rollback();return True
    except Exception:return False


class PooledConnectionWrapper:
    def __init__(self, pool, conn):self._pool=pool;self._conn=conn;self._closed=False
    def close(self):
        if self._closed:return
        self._closed=True
        if not self._pool or self._pool.closed:
            try:self._conn.close()
            except Exception:pass
            return
        try:
            if self._conn.closed:raise RuntimeError('connection is closed')
            self._conn.rollback()
        except Exception:_discard_connection(self._pool,self._conn)
        else:self._pool.putconn(self._conn)
    def __getattr__(self,name):return getattr(self._conn,name)
    def __enter__(self):
        self._conn.__enter__()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        try:
            return self._conn.__exit__(exc_type, exc_val, exc_tb)
        finally:
            self.close()


def get_db_connection():
    try:
        pool=_get_pool()
        for _ in range(2):
            raw_conn=pool.getconn()
            if _connection_is_usable(raw_conn):return PooledConnectionWrapper(pool,raw_conn)
            _discard_connection(pool,raw_conn)
        raise RuntimeError('pooled database connections failed validation')
    except Exception:
        import psycopg2
        from psycopg2.extras import RealDictCursor
        return psycopg2.connect(_database_url(), cursor_factory=RealDictCursor)


def fetch_one(sql, params=()):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:cur.execute(sql,params);return cur.fetchone()
    finally:conn.close()


def fetch_all(sql, params=()):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:cur.execute(sql,params);return cur.fetchall()
    finally:conn.close()


def execute(sql, params=(), returning=False):
    conn=get_db_connection()
    try:
        with conn.cursor() as cur:
            cur.execute(sql,params);row=cur.fetchone() if returning else None
        conn.commit();return row
    except Exception:
        conn.rollback();raise
    finally:conn.close()
