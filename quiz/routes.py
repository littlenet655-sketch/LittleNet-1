from flask import Blueprint,render_template,request,redirect,session
from decorators import child_required,parent_required
from quiz.service import quizzes,reset,learning_challenges,learning_points
from parent.service import owns,children
from database.connection import fetch_one,fetch_all,execute

quiz_bp=Blueprint('quiz',__name__,template_folder='templates')

@quiz_bp.route('/quiz/start/')
@child_required
def start():
    qs=quizzes(session['user_id'],5)
    if not qs:return render_template('quiz_result.html',error='No age-group questions available yet.')
    session['quiz_ids']=[q['quiz_id'] for q in qs];session['quiz_index']=0;session['quiz_score']=0
    return render_template('quiz_card.html',quiz=qs[0],question_number=1,total_questions=len(qs))

@quiz_bp.route('/quiz/submit/',methods=['POST'])
@child_required
def submit():
    ids=session.get('quiz_ids') or [];idx=int(session.get('quiz_index',0))
    if idx>=len(ids):return redirect('/quiz/start/')
    expected=ids[idx]
    try:posted=int(request.form.get('quiz_id',0))
    except:return redirect('/quiz/start/')
    if posted!=expected:return ('Invalid quiz state',400)
    q=fetch_one('SELECT * FROM quizzes WHERE quiz_id=%s',(expected,));ans=request.form.get('answer','');correct=bool(q and ans==q['correct_answer'])
    execute('INSERT INTO child_quiz_attempts(child_id,quiz_id,selected_answer,is_correct) VALUES(%s,%s,%s,%s)',(session['user_id'],expected,ans,correct))
    session['quiz_score']=session.get('quiz_score',0)+(1 if correct else 0);idx+=1;session['quiz_index']=idx
    if idx>=len(ids):
        score=session['quiz_score'];total=len(ids);session.pop('quiz_ids',None);session.pop('quiz_index',None);session.pop('quiz_score',None);reset(session['user_id'])
        return render_template('quiz_result.html',score=score,total=total)
    return render_template('quiz_card.html',quiz=fetch_one('SELECT * FROM quizzes WHERE quiz_id=%s',(ids[idx],)),question_number=idx+1,total_questions=len(ids))

@quiz_bp.route('/quiz/settings/',methods=['GET','POST'])
@parent_required
def settings():
    kids=children(session['user_id']);cid=int(request.values.get('child_id') or (kids[0]['user_id'] if kids else 0))
    if not owns(session['user_id'],cid):return ('Forbidden',403)
    if request.method=='POST':
        try:f=int(request.form.get('quiz_frequency',5))
        except:return ('Invalid frequency',400)
        if not 1<=f<=50:return ('Frequency 1-50',400)
        execute('INSERT INTO parent_quiz_settings(parent_id,child_id,quiz_frequency,mandatory_quiz) VALUES(%s,%s,%s,%s) ON CONFLICT(child_id) DO UPDATE SET quiz_frequency=EXCLUDED.quiz_frequency,mandatory_quiz=EXCLUDED.mandatory_quiz',(session['user_id'],cid,f,'mandatory_quiz' in request.form))
        return redirect(f'/quiz/settings/?child_id={cid}')
    return render_template('parent_quiz_settings.html',child_id=cid,settings=fetch_one('SELECT * FROM parent_quiz_settings WHERE child_id=%s',(cid,)))

@quiz_bp.route('/parent/quiz-report/')
@parent_required
def report():
    kids=children(session['user_id']);cid=int(request.args.get('child_id') or (kids[0]['user_id'] if kids else 0))
    if not owns(session['user_id'],cid):return ('Forbidden',403)
    rows=fetch_all('SELECT a.*,q.question FROM child_quiz_attempts a JOIN quizzes q ON q.quiz_id=a.quiz_id WHERE a.child_id=%s ORDER BY attempted_at DESC',(cid,))
    return render_template('parent_quiz_report.html',attempts=rows)

@quiz_bp.route('/quiz/save-settings/',methods=['POST'])
@parent_required
def save_settings_alias():return settings()

@quiz_bp.route('/learning/')
@child_required
def learning():
    return render_template('learning.html',challenges=learning_challenges(session['user_id']),points=learning_points(session['user_id']))

@quiz_bp.route('/learning/challenge/<int:challenge_id>/',methods=['POST'])
@child_required
def complete_challenge(challenge_id):
    q=fetch_one('SELECT * FROM learning_challenges WHERE challenge_id=%s AND active=TRUE',(challenge_id,))
    if not q:return ('Challenge not found',404)
    allowed={x['challenge_id'] for x in learning_challenges(session['user_id'])}
    if challenge_id not in allowed:return ('Challenge not available for this age group',403)
    response=(request.form.get('response') or '').strip();expected=(q.get('expected_answer') or '').strip()
    correct=True if not expected else response.casefold()==expected.casefold()
    points=q['points'] if correct else 0
    execute('''INSERT INTO learning_challenge_attempts(child_id,challenge_id,response,completed,points_awarded)
      VALUES(%s,%s,%s,TRUE,%s)
      ON CONFLICT(child_id,challenge_id) DO UPDATE SET response=EXCLUDED.response,completed=TRUE,points_awarded=EXCLUDED.points_awarded,completed_at=NOW()''',
      (session['user_id'],challenge_id,response,points))
    return redirect('/learning/')

@quiz_bp.route('/parent/learning-report/')
@parent_required
def learning_report():
    kids=children(session['user_id']);cid=int(request.args.get('child_id') or (kids[0]['user_id'] if kids else 0))
    if not owns(session['user_id'],cid):return ('Forbidden',403)
    rows=fetch_all('''SELECT a.*,c.title,c.challenge_type,c.points FROM learning_challenge_attempts a
      JOIN learning_challenges c ON c.challenge_id=a.challenge_id WHERE a.child_id=%s ORDER BY a.completed_at DESC''',(cid,))
    child=fetch_one('SELECT full_name FROM users WHERE user_id=%s',(cid,)) or {'full_name':'Child'}
    return render_template('parent_learning_report.html',rows=rows,child=child,child_id=cid)
