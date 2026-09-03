from pathlib import Path
import argparse
from dotenv import load_dotenv
load_dotenv(Path(__file__).parents[1]/'.env')
from database.connection import get_db_connection

root=Path(__file__).parents[1]
parser=argparse.ArgumentParser(description='Initialize/update LittleNet PostgreSQL schema.')
parser.add_argument('--seed',action='store_true',help='also insert the academic demo quiz seed data')
args=parser.parse_args()
conn=get_db_connection()
try:
    with conn.cursor() as cur:
        cur.execute((root/'database/schema.sql').read_text())
        cur.execute((root/'database/upgrade.sql').read_text())
        if args.seed:cur.execute((root/'database/seed.sql').read_text())
    conn.commit();print('LittleNet database schema initialized.'+(' Demo seed applied.' if args.seed else ''))
except Exception:
    conn.rollback();raise
finally:conn.close()
