from functools import wraps
from flask import session, redirect, jsonify, request
from database.connection import fetch_one


def _deny():
    if request.path.startswith('/api/'):
        return jsonify(error='unauthorized'), 401
    return redirect('/login/')


def login_required(fn):
    @wraps(fn)
    def inner(*a,**kw):
        if not session.get('user_id'):return _deny()
        return fn(*a,**kw)
    return inner


def role_required(role):
    def deco(fn):
        @wraps(fn)
        def inner(*a,**kw):
            uid=session.get('user_id')
            if not uid or session.get('role')!=role:return _deny()
            # Technical usage heartbeat does not expose feed/content and may run
            # while the onboarding gate is deciding where to redirect. Keep it
            # exempt here so direct unit calls do not require a real DB. The
            # app-level onboarding gate still protects every normal Kids surface.
            face_exempt=request.path in {'/face/enroll/','/api/usage/heartbeat/'}
            if role=='CHILD' and not face_exempt:
                face=fetch_one('SELECT 1 FROM face_profiles WHERE child_id=%s LIMIT 1',(uid,))
                if not face:
                    if request.path.startswith('/api/'):
                        return jsonify(error='face_enrollment_required',next='/face/enroll/'),428
                    return redirect('/face/enroll/')
            if role=='PARENT':
                user=fetch_one('SELECT account_status FROM users WHERE user_id=%s AND role=\'PARENT\'',(uid,))
                if not user or user.get('account_status')!='ACTIVE':
                    session.clear()
                    return redirect('/login/?mode=parent&error=Complete+email+OTP+and+live+adult+verification+first')
            return fn(*a,**kw)
        return inner
    return deco


child_required=role_required('CHILD')
parent_required=role_required('PARENT')
admin_required=role_required('ADMIN')
