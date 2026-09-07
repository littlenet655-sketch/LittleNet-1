from functools import wraps
from flask import session, redirect, jsonify, request
from database.connection import fetch_one


def _deny():
    if request.path.startswith('/api/'):
        return jsonify(error='unauthorized'), 401
    return redirect('/login/')


def _inactive(role):
    session.clear()
    if request.path.startswith('/api/') or request.is_json:
        return jsonify(error='account_inactive'), 403
    mode='parent' if role=='PARENT' else ('kids' if role=='CHILD' else 'admin')
    return redirect(f'/login/?mode={mode}&error=This+account+is+inactive+or+suspended')


def login_required(fn):
    @wraps(fn)
    def inner(*a,**kw):
        uid=session.get('user_id')
        if not uid:return _deny()
        role=session.get('role')
        if role in {'CHILD','PARENT','ADMIN'}:
            user=fetch_one('SELECT account_status,role FROM users WHERE user_id=%s',(uid,))
            if not user or user.get('role')!=role or user.get('account_status')!='ACTIVE':
                return _inactive(role)
        return fn(*a,**kw)
    return inner


def role_required(role):
    def deco(fn):
        @wraps(fn)
        def inner(*a,**kw):
            uid=session.get('user_id')
            if not uid or session.get('role')!=role:return _deny()

            # Re-check the database on every authenticated request so Parent/Admin
            # suspension and emergency child pause revoke already-issued sessions.
            user=fetch_one('SELECT account_status,role FROM users WHERE user_id=%s',(uid,))
            if not user or user.get('role')!=role or user.get('account_status')!='ACTIVE':
                return _inactive(role)

            if role=='CHILD':
                # Parent Mode's Discover switch is a server-side control, not just
                # a navigation preference. Cover every search/profile/follow surface.
                discover_paths=(
                    '/discover/','/api/discover/','/api/search/suggestions/',
                    '/child/view-profile/','/follow/','/recommended/'
                )
                if request.path.startswith(discover_paths):
                    from services.controls import feature_allowed
                    if not feature_allowed(uid,'discover'):
                        if request.path.startswith('/api/') or request.is_json or request.method!='GET':
                            return jsonify(error='disabled_by_parent',feature='discover'),403
                        return redirect('/child/dashboard/')

                # Editing must never become a PII bypass after a story was initially
                # moderated. Re-run deterministic PII policy before the route writes.
                if request.method=='POST' and request.path.startswith('/api/edit-story-caption/'):
                    from safety.pii_service import scan_pii
                    data=request.get_json(silent=True) or {}
                    if scan_pii((data.get('caption') or '').strip()).get('detected'):
                        return jsonify(ok=False,error='Personal contact information cannot be shared in story captions.'),400

                # Technical usage heartbeat does not expose feed/content and may run
                # while the onboarding gate is deciding where to redirect.
                face_exempt=request.path in {'/face/enroll/','/api/usage/heartbeat/'}
                if not face_exempt:
                    face=fetch_one('SELECT 1 FROM face_profiles WHERE child_id=%s LIMIT 1',(uid,))
                    if not face:
                        if request.path.startswith('/api/'):
                            return jsonify(error='face_enrollment_required',next='/face/enroll/'),428
                        return redirect('/face/enroll/')

            if role=='PARENT':
                # Legacy quick approval can bypass the verified guardian state
                # machine. Keep the endpoint fail-closed; verified flows use the
                # explicit token/session approval service instead.
                if request.path.rstrip('/')=='/parent/quick-approve-child':
                    return ('Legacy quick approval is disabled. Complete guardian verification.',410)
                # The old GET confirmation route performed a state change. It is no
                # longer part of the verified-parent provisioning flow, so GET is
                # deliberately non-actionable instead of activating a child.
                if request.method=='GET' and request.path.startswith('/parent/confirm-child/'):
                    return ('Legacy email-only child activation is disabled. Use verified Parent Mode.',410)

            return fn(*a,**kw)
        return inner
    return deco


child_required=role_required('CHILD')
parent_required=role_required('PARENT')
admin_required=role_required('ADMIN')
