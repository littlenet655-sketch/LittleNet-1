"""Static scope guard for the corrected LittleNet PPT + locked final additions."""
from pathlib import Path
import sys
R=Path(__file__).parents[1]
checks={
 'Kids Mode feed':('child/routes.py','/child/dashboard/'),
 'Posts/upload':('uploadPost/routes.py','/child/upload-post/'),
 'Reels':('uploadPost/routes.py','/reels/'),
 'Messages/chat':('childMessage/routes.py','/messages/'),
 'Recommended users/feed':('child/service.py','recommended_posts'),
 'Discover':('child/routes.py','/discover/'),
 'Likes/comments/sharing':('templates/_post.html','data-share-post'),
 'Save/bookmark':('uploadPost/routes.py','/saved/'),
 'Stories':('child/routes.py','/stories/'),
 '18+ hard block':('safety/policy.py','18+ content hard blocked'),
 'NSFW visual moderation':('safety/visual_service.py','Falconsai/nsfw_image_detection'),
 'YOLO weapon detection':('safety/visual_service.py','YOLO'),
 'Whisper audio':('safety/audio_service.py','faster_whisper'),
 'Cyberbullying/toxic NLP':('safety/text_service.py','CYBERBULLYING'),
 'Risk ALLOW/REVIEW/BLOCK':('safety/policy.py',"Decision('REVIEW'"),
 'Parent review':('parent/routes.py','/parent/review/'),
 'Parent-first account flow':('parent/routes.py','/parent/create-child/'),
 'Screen time':('services/usage.py','SCREEN_TIME_LIMIT_REACHED'),
 'Parent alert persistence':('services/social.py','parent_notifications'),
 'Real-time parent alerts':('static/js/littlenet.js','pollParentAlerts'),
 'Smart parent controls':('services/controls.py','educational_only_feed'),
 'Age-targeted personalized feed':('services/social.py','audience_age_group'),
 'AI semantic personalized feed':('services/recommendation.py','remote_client.rank_texts'),
 'Multilingual UI':('services/i18n.py',"'KN':'ಕನ್ನಡ'"),
 'Quizzes':('quiz/routes.py','/quiz/start/'),
 'Learning challenges':('quiz/routes.py','/learning/challenge/'),
 'Educational Reels':('uploadPost/templates/reels.html',"t('educational_reel')"),
 'Admin/Moderator':('admin/routes.py','/admin/moderation/'),
 'Behavioral analysis':('services/behavior.py','behavior_summary'),
 'Live moderation':('child/routes.py','/api/live-safety/check/'),
 'Face Login/liveness':('safety/face_service.py','anti_spoofing=True'),
 'Privacy/security headers':('app.py','Content-Security-Policy'),
 'PostgreSQL activity logs':('database/schema.sql','CREATE TABLE IF NOT EXISTS activity_logs'),
 'Android APK source':('android/app/src/main/java/com/littlenet/app/MainActivity.java','WebView'),
 'Modal AI deployment':('modal_ai.py','gpu="T4"'),
 'Quiet hours':('services/controls.py','quiet_hours_state'),
 'Parent home live metrics':('parent/routes.py',"k['presence']=online_state(cid)"),
 'Approved-only interaction':('uploadPost/routes.py','approved connection required'),
 'Non-global Discover':('child/service.py','approved_friends AS'),
 'Safety email alerts':('services/social.py','LittleNet safety alert'),
 'Admin post removal':('admin/routes.py','/admin/post/<int:post_id>/remove/'),
}
errors=[]
for name,(rel,needle) in checks.items():
    p=R/rel
    ok=p.exists() and needle in p.read_text(encoding='utf-8')
    print(('PASS' if ok else 'FAIL'),name)
    if not ok:errors.append(name)
print(f'\nSCOPE_CHECK={len(checks)-len(errors)}/{len(checks)}')
sys.exit(bool(errors))
