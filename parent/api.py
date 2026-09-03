from flask import Blueprint,jsonify,session
from decorators import parent_required
from parent.service import children,owns
from database.connection import fetch_one
parent_api_bp=Blueprint('parent_api',__name__)
@parent_api_bp.route('/api/parent/children/')
@parent_required
def api_children():return jsonify(success=True,children=children(session['user_id']))
@parent_api_bp.route('/api/parent/child/<int:child_id>/')
@parent_required
def api_child(child_id):
    if not owns(session['user_id'],child_id):return jsonify(success=False),404
    return jsonify(success=True,profile=fetch_one('SELECT * FROM child_profiles WHERE child_id=%s',(child_id,)))

@parent_api_bp.route('/api/parent/children/<int:parent_id>/')
@parent_required
def api_children_compat(parent_id):
    if parent_id!=session['user_id']:return jsonify(success=False),403
    return jsonify(success=True,children=children(session['user_id']))
