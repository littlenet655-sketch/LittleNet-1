"""Apply idempotent upgrades to an existing LittleNet PostgreSQL database."""
from pathlib import Path
from database.connection import get_db_connection
root=Path(__file__).parents[1]
conn=get_db_connection()
try:
    with conn.cursor() as cur:cur.execute((root/'database/upgrade.sql').read_text())
    conn.commit();print('LittleNet database upgrade: PASS')
except Exception:
    conn.rollback();raise
finally:conn.close()
