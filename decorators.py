from functools import wraps
from flask import session, redirect, jsonify, request

def _deny():
    if request.path.startswith('/api/'):
        return jsonify(error='unauthorized'), 401
    return redirect('/login/')

def login_required(fn):
    @wraps(fn)
    def inner(*a,**kw):
        if not session.get('user_id'): return _deny()
        return fn(*a,**kw)
    return inner

def role_required(role):
    def deco(fn):
        @wraps(fn)
        def inner(*a,**kw):
            if not session.get('user_id') or session.get('role') != role: return _deny()
            return fn(*a,**kw)
        return inner
    return deco
child_required=role_required('CHILD')
parent_required=role_required('PARENT')
admin_required=role_required('ADMIN')
