import os,uuid
from flask import Blueprint,render_template,request,redirect,session,jsonify
from decorators import child_required
from database.connection import fetch_all,fetch_one,execute
from services.social import can_interact,parent_notify,post_visible_to,notify
from childMessage.service import conversation,messages
from safety.moderation_service import evaluate,record
from services.audit import log

child_message_bp=Blueprint('child_message',__name__,template_folder='templates')
@child_message_bp.route('/messages/')
@child_required
def list_messages():
    rows=fetch_all("SELECT c.*,CASE WHEN c.child1_id=%s THEN u2.full_name ELSE u1.full_name END peer_name,CASE WHEN c.child1_id=%s THEN c.child2_id ELSE c.child1_id END peer_id FROM child_conversations c JOIN users u1 ON u1.user_id=c.child1_id JOIN users u2 ON u2.user_id=c.child2_id WHERE (c.child1_id=%s OR c.child2_id=%s)",(session['user_id'],session['user_id'],session['user_id'],session['user_id']))
    rows=[r for r in rows if can_interact(session['user_id'],r['peer_id'])];return render_template('chat_list.html',conversations=rows)
@child_message_bp.route('/chat/<int:child_id>/')
@child_required
def chat(child_id):
    cid=conversation(session['user_id'],child_id)
    if not cid:return ('Parent-approved connection required',403)
    execute('UPDATE child_messages SET is_seen=TRUE,seen_at=NOW(),delivered_at=COALESCE(delivered_at,NOW()) WHERE conversation_id=%s AND receiver_child_id=%s AND moderation_status=\'ALLOWED\'',(cid,session['user_id']))
    return render_template('chat.html',messages=messages(cid,session['user_id']),peer_id=child_id,conversation_id=cid)
@child_message_bp.route('/send-message/<int:child_id>/',methods=['POST'])
@child_required
def send_text(child_id):
    if not can_interact(session['user_id'],child_id):return jsonify(error='approved connection required'),403
    text=(request.form.get('message_text') or '').strip();sig,d=evaluate(session['user_id'],'TEXT',text)
    if d.action=='BLOCK':parent_notify(session['user_id'],'MESSAGE_BLOCKED',d.reason,'/parent/safety/');return jsonify(blocked=True),400
    cid=conversation(session['user_id'],child_id);row=execute("INSERT INTO child_messages(conversation_id,sender_child_id,receiver_child_id,message_type,message_text,moderation_status) VALUES(%s,%s,%s,'TEXT',%s,%s) RETURNING child_message_id",(cid,session['user_id'],child_id,text,'ALLOWED' if d.action=='ALLOW' else 'REVIEW'),returning=True);record(session['user_id'],'MESSAGE',row['child_message_id'],sig,d)
    if d.action=='REVIEW':parent_notify(session['user_id'],'REVIEW_REQUIRED','A message needs review','/parent/safety/')
    else:notify(child_id,'MESSAGE',f'{session.get("full_name","Someone")} sent you a message',f'/chat/{session["user_id"]}/',session['user_id'])
    log(session['user_id'],'MESSAGE_SENT',{'to':child_id,'status':d.action})
    return redirect(f'/chat/{child_id}/')
@child_message_bp.route('/share-post/<int:child_id>/<int:post_id>/',methods=['POST'])
@child_required
def share_post(child_id,post_id):
    if not can_interact(session['user_id'],child_id):return jsonify(error='approved connection required'),403
    p=post_visible_to(session['user_id'],post_id)
    if not p:return jsonify(error='post unavailable'),404
    cid=conversation(session['user_id'],child_id);execute("INSERT INTO child_messages(conversation_id,sender_child_id,receiver_child_id,message_type,shared_post_id,moderation_status) VALUES(%s,%s,%s,'SHARED_POST',%s,'ALLOWED')",(cid,session['user_id'],child_id,post_id));notify(child_id,'MESSAGE',f'{session.get("full_name","Someone")} shared a post with you',f'/chat/{session["user_id"]}/',session['user_id']);return jsonify(ok=True)

@child_message_bp.route('/send-media/<int:child_id>/',methods=['POST'])
@child_required
def send_media(child_id):
    if not can_interact(session['user_id'],child_id):return jsonify(error='approved connection required'),403
    media=request.files.get('media')
    if not media or not media.filename:return jsonify(error='no file'),400
    if request.content_length and request.content_length>40*1024*1024:return jsonify(error='file too large'),413
    name=media.filename.lower();ext=name.rsplit('.',1)[-1] if '.' in name else '';mime=(media.mimetype or '').lower()
    if ext in {'jpg','jpeg','png','webp'}:kind='IMAGE';folder='images'
    elif ext in {'mp4','mov','avi','mkv','webm'} and not mime.startswith('audio/'):kind='VIDEO';folder='videos'
    elif ext in {'mp3','wav','m4a','ogg','webm'} and (mime.startswith('audio/') or ext!='webm'):kind='VOICE';folder='audio'
    elif ext in {'txt','pdf','docx'}:kind='FILE';folder='files'
    else:return jsonify(error='unsupported file type'),400
    base=os.path.join('uploads/messages',folder);os.makedirs(base,exist_ok=True);path=os.path.join(base,f'{uuid.uuid4().hex}.{ext}');media.save(path)
    try:
        if kind=='FILE':
            from safety.document_service import check_document
            from safety.policy import decide
            from safety.moderation_service import safety_level
            sig=check_document(path,ext);d=decide(sig,safety_level(session['user_id']))
        else:
            sig,d=evaluate(session['user_id'],kind,path)
        if d.action=='BLOCK':
            try:os.remove(path)
            except OSError:pass
            parent_notify(session['user_id'],'MESSAGE_MEDIA_BLOCKED',d.reason,'/parent/safety/');return jsonify(blocked=True,reason=d.reason),400
        cid=conversation(session['user_id'],child_id)
        row=execute('INSERT INTO child_messages(conversation_id,sender_child_id,receiver_child_id,message_type,media_path,moderation_status) VALUES(%s,%s,%s,%s,%s,%s) RETURNING child_message_id',(cid,session['user_id'],child_id,kind,path,'ALLOWED' if d.action=='ALLOW' else 'REVIEW'),returning=True)
        record(session['user_id'],'MESSAGE',row['child_message_id'],sig,d)
        if d.action=='REVIEW':parent_notify(session['user_id'],'REVIEW_REQUIRED','A media message needs review','/parent/safety/')
        else:notify(child_id,'MESSAGE',f'{session.get("full_name","Someone")} sent you {kind.lower()} media',f'/chat/{session["user_id"]}/',session['user_id'])
        return jsonify(ok=True,status=d.action)
    except Exception:
        try:os.remove(path)
        except OSError:pass
        return jsonify(error='media safety check failed'),503

@child_message_bp.route('/api/chat/<int:child_id>/messages/')
@child_required
def api_chat_messages(child_id):
    cid=conversation(session['user_id'],child_id)
    if not cid:return jsonify(error='approved connection required'),403
    rows=messages(cid,session['user_id'])
    return jsonify([{k:(str(v) if k=='sent_at' else v) for k,v in r.items()} for r in rows])
