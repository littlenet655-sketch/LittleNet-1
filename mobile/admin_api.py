from __future__ import annotations

from flask import g, jsonify, request

from database.connection import fetch_all, fetch_one, get_db_connection
from extensions import csrf, limiter
from mobile.api import _clean, _require_mobile


def register_mobile_admin_api(bp):
    @bp.route('/api/mobile/v1/admin/reviews/<int:event_id>', methods=['GET', 'POST'])
    @csrf.exempt
    @limiter.limit('60 per minute')
    @_require_mobile('ADMIN')
    def mobile_admin_review_detail(event_id):
        event = fetch_one(
            """SELECT e.*,u.full_name,u.username
               FROM moderation_events e JOIN users u ON u.user_id=e.child_id
               WHERE e.event_id=%s""",
            (event_id,),
        )
        if not event:
            return jsonify(error='review_not_found'), 404

        if request.method == 'GET':
            preview = None
            ctype = event.get('content_type')
            cid = event.get('content_id')
            if cid and ctype in {'IMAGE', 'VIDEO', 'TEXT'}:
                preview = fetch_one('SELECT media_type,media_path,caption,moderation_status FROM posts WHERE post_id=%s', (cid,))
            elif cid and ctype == 'COMMENT':
                preview = fetch_one('SELECT comment_text,moderation_status FROM comments WHERE comment_id=%s', (cid,))
            elif cid and ctype == 'MESSAGE':
                preview = fetch_one('SELECT message_type,message_text,media_path,moderation_status FROM child_messages WHERE child_message_id=%s', (cid,))
            return jsonify(ok=True, event=_clean(event), preview=_clean(preview))

        data = request.get_json(silent=True) or {}
        requested = str(data.get('action') or '').upper()
        if requested not in {'APPROVE', 'BLOCK', 'ESCALATE'}:
            return jsonify(error='invalid_action'), 400

        conn = get_db_connection()
        try:
            cur = conn.cursor()
            cur.execute("SELECT * FROM moderation_events WHERE event_id=%s AND status='OPEN' FOR UPDATE", (event_id,))
            locked = cur.fetchone()
            if not locked:
                conn.rollback()
                return jsonify(error='review_already_resolved'), 409

            if requested == 'ESCALATE':
                # Keep the incident open but make the escalation explicit in the immutable review trail.
                cur.execute(
                    'INSERT INTO moderation_reviews(event_id,reviewer_id,action,notes) VALUES(%s,%s,%s,%s)',
                    (event_id, g.mobile_user['user_id'], 'ESCALATE', str(data.get('notes') or 'Escalated by moderator')),
                )
                conn.commit()
                return jsonify(ok=True, action='ESCALATE', status='OPEN')

            db_status = 'ALLOWED' if requested == 'APPROVE' else 'BLOCKED'
            safe = requested == 'APPROVE'
            ctype = locked.get('content_type')
            cid = locked.get('content_id')
            if cid and ctype in {'IMAGE', 'VIDEO', 'TEXT'}:
                cur.execute('UPDATE posts SET moderation_status=%s,is_safe=%s WHERE post_id=%s', (db_status, safe, cid))
            elif cid and ctype == 'COMMENT':
                cur.execute('UPDATE comments SET moderation_status=%s WHERE comment_id=%s', (db_status, cid))
            elif cid and ctype == 'MESSAGE':
                cur.execute('UPDATE child_messages SET moderation_status=%s WHERE child_message_id=%s', (db_status, cid))

            cur.execute(
                'INSERT INTO moderation_reviews(event_id,reviewer_id,action,notes) VALUES(%s,%s,%s,%s)',
                (event_id, g.mobile_user['user_id'], requested, str(data.get('notes') or '') or None),
            )
            cur.execute("UPDATE moderation_events SET status='RESOLVED' WHERE event_id=%s", (event_id,))
            conn.commit()
            return jsonify(ok=True, action=requested, status='RESOLVED')
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    @bp.route('/api/mobile/v1/admin/users')
    @_require_mobile('ADMIN')
    def mobile_admin_users():
        q = str(request.args.get('q') or '').strip()
        pattern = f'%{q}%'
        rows = fetch_all(
            """SELECT user_id,username,full_name,email,role,age,account_status,created_at
               FROM users
               WHERE (%s='' OR full_name ILIKE %s OR username ILIKE %s OR email ILIKE %s)
               ORDER BY created_at DESC LIMIT 100""",
            (q, pattern, pattern, pattern),
        )
        return jsonify(ok=True, users=_clean(rows))

    @bp.route('/api/mobile/v1/admin/users/<int:target_user_id>/status', methods=['POST'])
    @csrf.exempt
    @limiter.limit('30 per minute')
    @_require_mobile('ADMIN')
    def mobile_admin_user_status(target_user_id):
        data = request.get_json(silent=True) or {}
        new_status = str(data.get('status') or '').upper()
        if new_status not in {'ACTIVE', 'SUSPENDED'}:
            return jsonify(error='invalid_status'), 400
        if int(target_user_id) == int(g.mobile_user['user_id']):
            return jsonify(error='cannot_modify_self'), 400
        conn = get_db_connection()
        try:
            cur = conn.cursor()
            cur.execute("UPDATE users SET account_status=%s WHERE user_id=%s", (new_status, target_user_id))
            cur.execute(
                "INSERT INTO activity_logs(child_id, activity_type, activity_data) VALUES(%s, 'ADMIN_USER_STATUS_CHANGE', %s::jsonb)",
                (target_user_id, __import__('json').dumps({'admin_id': g.mobile_user['user_id'], 'new_status': new_status}))
            )
            conn.commit()
            return jsonify(ok=True, user_id=target_user_id, status=new_status)
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()

    @bp.route('/api/mobile/v1/admin/audit')
    @_require_mobile('ADMIN')
    def mobile_admin_audit():
        rows = fetch_all(
            """SELECT * FROM activity_logs ORDER BY created_at DESC LIMIT 100"""
        )
        return jsonify(ok=True, events=_clean(rows))

