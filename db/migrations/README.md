# LittleNet dbmate migrations

LittleNet adopted **dbmate** after the original PostgreSQL schema and idempotent
`database/upgrade.sql` / `database/friendship_upgrade.sql` files were already in
use. To protect existing Neon databases, deployment currently does this:

1. run `tools/init_db.py` as the legacy/idempotent bootstrap;
2. run `dbmate --strict --no-dump-schema up`;
3. create every **new** schema change as a timestamped file in this directory.

Do not copy the historical full schema into a new migration and replay it against
an existing database. The adoption marker is intentionally a no-op boundary.

Create future migrations with:

```bash
dbmate new descriptive_change_name
```

Each migration must contain both `-- migrate:up` and `-- migrate:down`, use
PostgreSQL-safe transactional DDL where possible, and be exercised on a disposable
staging database before production.
