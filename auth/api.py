from flask import Blueprint,request,jsonify,session
from extensions import csrf,limiter
from auth.service import login_user,profile_exists
from services.usage import start_session
api_bp=Blueprint('api',__name__)
@api_bp.route('/api/login/',methods=['POST'])
@csrf.exempt
@limiter.limit('10 per minute')
def api_login():
    d=request.get_json(silent=True) or {}; u=login_user(d.get('email',''),d.get('password',''))
    if not u:return jsonify(success=False,message='Invalid credentials'),401
    session.clear(); session['user_id']=u['user_id'];session['role']=u['role'];session['full_name']=u['full_name']
    if u['role']=='CHILD': session['usage_session_key']=str(start_session(u['user_id'])['session_key'])
    return jsonify(success=True,role=u['role'],user_id=u['user_id'],full_name=u['full_name'],has_profile=profile_exists(u['user_id']) if u['role']=='CHILD' else True)
