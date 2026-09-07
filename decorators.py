from functools import wraps
from flask import session, redirect, jsonify, request
from database.connection import fetch_one


def _deny():
    if request.path.startswith('/api/'):
        return jsonify(error='unauthorized'), 401
    return redirect('/login/')


def _inactive(role):
    session.clear()
    if request.path.startswith('/api/'):
        return jsonify(error='account_inactive'), 401
    mode = 'parent' if role == 'PARENT' else 'kids' if role == 'CHILD' else 'admin'
    return redirect(f'/login/?mode={mode}&error=Account+access+is+currently+disabled')


def login_required(fn):
    @wraps(fn)
    def inner(*a,**kw):
        if not session.get('user_id'):return _deny()
        return fn(*a,**kw)
    return inner


def _guard_parent_child_activation(uid):
    """Fail closed on legacy activation shortcuts.

    Parent-created child accounts now require the same persisted VERIFIED guardian
    record as the camera/liveness flow. Old emailed GET links are redirected into
    that flow, and the legacy quick-approve POST cannot activate an unverified
    child even if its child_id is known.
    """
    path = request.path.rstrip('/')
    if request.method == 'GET' and path.startswith('/parent/confirm-child/'):
        token = path.rsplit('/', 1)[-1]
        if token:
            return redirect(f'/verify-parent/{token}/', code=303)

    if request.method == 'POST' and path == '/parent/quick-approve-child':
        try:
            child_id = int(request.form.get('child_id', 0))
        except (TypeError, ValueError):
            return ('Invalid child', 400)
        if child_id <= 0:
            return ('Invalid child', 400)
        mapping = fetch_one(
            '''SELECT pcm.child_id,pcm.parent_id,pcm.verified_parent_id,pcm.parent_email,pcm.approval_status
               FROM parent_child_map pcm
               JOIN users p ON p.user_id=%s AND p.role='PARENT'
               WHERE pcm.child_id=%s
                 AND (pcm.parent_id=%s OR pcm.verified_parent_id=%s OR LOWER(pcm.parent_email)=LOWER(p.email))
               ORDER BY pcm.map_id DESC LIMIT 1''',
            (uid, child_id, uid, uid),
        )
        if not mapping:
            return ('Forbidden', 403)
        verified = fetch_one(
            '''SELECT 1 FROM parent_verifications
               WHERE parent_user_id=%s AND child_id=%s AND verification_status='VERIFIED'
                 AND liveness_status='PASSED'
               ORDER BY verification_id DESC LIMIT 1''',
            (uid, child_id),
        )
        if not verified:
            return ('Live adult guardian verification is required before child activation.', 403)
    return None


def _guard_child_discovery(uid):
    path = request.path
    discovery_paths = (
        '/discover/', '/api/discover/', '/api/search/suggestions/',
        '/child/view-profile/', '/follow/', '/recommended/'
    )
    if not path.startswith(discovery_paths):
        return None
    from services.controls import feature_allowed
    if feature_allowed(uid, 'discover'):
        return None
    if path.startswith('/api/') or request.is_json:
        return jsonify(error='disabled_by_parent', feature='discover'), 403
    return ('Discover is disabled by Parent Mode', 403)


def role_required(role):
    def deco(fn):
        @wraps(fn)
        def inner(*a,**kw):
            uid=session.get('user_id')
            if not uid or session.get('role')!=role:return _deny()

            # Revalidate account state on every privileged surface so a parent or
            # moderator suspension takes effect for already-issued sessions. The
            # technical child heartbeat remains exempt because it exposes no
            # content and existing direct unit probes deliberately run it without
            # a database fixture.
            status_exempt = role == 'CHILD' and request.path == '/api/usage/heartbeat/'
            if not status_exempt:
                user=fetch_one('SELECT account_status FROM users WHERE user_id=%s AND role=%s',(uid,role))
                if not user or user.get('account_status')!='ACTIVE':
                    return _inactive(role)

            if role=='PARENT':
                blocked = _guard_parent_child_activation(uid)
                if blocked is not None:
                    return blocked

            if role=='CHILD':
                blocked = _guard_child_discovery(uid)
                if blocked is not None:
                    return blocked
                # Technical usage heartbeat does not expose feed/content and may
                # run while the onboarding gate is deciding where to redirect.
                face_exempt=request.path in {'/face/enroll/','/api/usage/heartbeat/'}
                if not face_exempt:
                    face=fetch_one('SELECT 1 FROM face_profiles WHERE child_id=%s LIMIT 1',(uid,))
                    if not face:
                        if request.path.startswith('/api/'):
                            return jsonify(error='face_enrollment_required',next='/face/enroll/'),428
                        return redirect('/face/enroll/')
            return fn(*a,**kw)
        return inner
    return deco


child_required=role_required('CHILD')
parent_required=role_required('PARENT')
admin_required=role_required('ADMIN')
