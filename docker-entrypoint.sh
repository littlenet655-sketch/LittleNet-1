#!/bin/sh
set -eu
mkdir -p /data/uploads /data/models /data/cache
rm -rf /app/uploads
ln -s /data/uploads /app/uploads
export HF_HOME="${HF_HOME:-/data/models/huggingface}"
export DEEPFACE_HOME="${DEEPFACE_HOME:-/data/models/deepface}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/data/cache}"

# Backward-safe migration transition: historical schema bootstrap remains
# idempotent; all post-adoption changes are tracked by dbmate.
python tools/init_db.py
if command -v dbmate >/dev/null 2>&1; then
  dbmate --strict --no-dump-schema --migrations-dir "${DBMATE_MIGRATIONS_DIR:-db/migrations}" up
fi

exec gunicorn app:app --bind "0.0.0.0:${PORT:-8080}" --workers 1 --threads 4 --timeout 240 --graceful-timeout 45 --access-logfile - --error-logfile -
