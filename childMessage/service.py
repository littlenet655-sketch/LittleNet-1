from database.connection import fetch_one,fetch_all,execute
from services.social import can_interact

def conversation(a,b):
    x,y=sorted((a,b));r=fetch_one('SELECT conversation_id FROM child_conversations WHERE child1_id=%s AND child2_id=%s',(x,y))
    if r:return r['conversation_id']
    if not can_interact(a,b):return None
    return execute('INSERT INTO child_conversations(child1_id,child2_id) VALUES(%s,%s) RETURNING conversation_id',(x,y),returning=True)['conversation_id']
def messages(cid,viewer):return fetch_all("SELECT m.*,u.full_name FROM child_messages m JOIN users u ON u.user_id=m.sender_child_id WHERE m.conversation_id=%s AND m.is_deleted=FALSE AND (m.moderation_status='ALLOWED' OR m.sender_child_id=%s) ORDER BY m.sent_at",(cid,viewer))
