"""Durable reconciliation for private R2 media queued by database triggers."""
from __future__ import annotations

from database.connection import execute, fetch_all


def enqueue_delete(reference: str, source_table: str = "compensation", source_id=None) -> None:
    """Persist a private-object deletion request for retry after transient failures."""
    if not reference or not str(reference).startswith("uploads/r2/"):
        return
    execute(
        """INSERT INTO media_delete_outbox(reference,source_table,source_id)
           VALUES(%s,%s,%s)
           ON CONFLICT(reference) DO UPDATE
             SET completed_at=NULL,last_error=NULL,source_table=EXCLUDED.source_table,
                 source_id=COALESCE(EXCLUDED.source_id,media_delete_outbox.source_id)""",
        (reference, source_table, source_id),
    )


def reconcile_pending_deletes(limit: int = 20) -> dict:
    try:
        limit = max(1, min(int(limit), 100))
    except (TypeError, ValueError):
        limit = 20
    rows = fetch_all(
        """SELECT outbox_id,reference FROM media_delete_outbox
           WHERE completed_at IS NULL ORDER BY created_at,outbox_id LIMIT %s""",
        (limit,),
    )
    completed = 0
    failed = 0
    from services.object_storage import delete_reference

    for row in rows:
        try:
            delete_reference(row["reference"])
            execute(
                """UPDATE media_delete_outbox
                   SET completed_at=COALESCE(completed_at,NOW()),
                       attempts=attempts+1,last_error=NULL
                   WHERE outbox_id=%s""",
                (row["outbox_id"],),
            )
            completed += 1
        except Exception as exc:
            execute(
                """UPDATE media_delete_outbox SET attempts=attempts+1,last_error=%s
                   WHERE outbox_id=%s""",
                (f"{type(exc).__name__}: {exc}"[:1000], row["outbox_id"]),
            )
            failed += 1
    return {"checked": len(rows), "completed": completed, "failed": failed}
