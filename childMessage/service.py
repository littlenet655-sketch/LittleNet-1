from database.connection import fetch_one,fetch_all,execute
from services.social import can_interact


def conversation(a,b):
    """Return/create a conversation only while the pair is currently authorized."""
    if not can_interact(a,b):return None
    x,y=sorted((a,b))
    r=fetch_one('SELECT conversation_id FROM child_conversations WHERE child1_id=%s AND child2_id=%s',(x,y))
    if r:return r['conversation_id']
    try:
        return execute('INSERT INTO child_conversations(child1_id,child2_id) VALUES(%s,%s) RETURNING conversation_id',(x,y),returning=True)['conversation_id']
    except Exception:
        # A concurrent request may have created the same unique pair.
        r=fetch_one('SELECT conversation_id FROM child_conversations WHERE child1_id=%s AND child2_id=%s',(x,y))
        return r['conversation_id'] if r and can_interact(a,b) else None


def messages(cid, viewer, limit=None, before_id=None):
    """Read messages only for an authorized participant pair using fixed SQL."""
    conv = fetch_one(
        'SELECT child1_id,child2_id FROM child_conversations WHERE conversation_id=%s AND (child1_id=%s OR child2_id=%s)',
        (cid, viewer, viewer),
    )
    if not conv:
        return []
    peer = conv['child2_id'] if conv['child1_id'] == viewer else conv['child1_id']
    if not can_interact(viewer, peer):
        return []
    safe_limit = int(limit) if limit is not None else 2147483647
    rows = fetch_all(
        """SELECT m.*, u.full_name
           FROM child_messages m
           JOIN users u ON u.user_id = m.sender_child_id
           WHERE m.conversation_id = %s AND m.is_deleted = FALSE
             AND (m.moderation_status = 'ALLOWED' OR m.sender_child_id = %s)
             AND (%s::bigint IS NULL OR m.child_message_id < %s::bigint)
           ORDER BY m.sent_at DESC, m.child_message_id DESC
           LIMIT %s""",
        (cid, viewer, before_id, before_id, safe_limit),
    )
    return list(reversed(rows))
