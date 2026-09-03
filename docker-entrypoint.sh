#!/bin/sh
set -eu
mkdir -p /data/uploads /data/models /data/cache
rm -rf /app/uploads
ln -s /data/uploads /app/uploads
export HF_HOME="${HF_HOME:-/data/models/huggingface}"
export DEEPFACE_HOME="${DEEPFACE_HOME:-/data/models/deepface}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/data/cache}"
python tools/init_db.py
exec gunicorn app:app --bind "0.0.0.0:${PORT:-8080}" --workers 1 --threads 4 --timeout 240 --graceful-timeout 45 --access-logfile - --error-logfile -
