import unittest,ast,re
from pathlib import Path
ROOT=Path(__file__).parents[1]
class Contracts(unittest.TestCase):
 def text(self,p):return (ROOT/p).read_text(encoding='utf-8')
 def test_python_parses(self):
  for p in ROOT.rglob('*.py'):
   if '__pycache__' not in p.parts:ast.parse(p.read_text(encoding='utf-8'))
 def test_no_git(self):self.assertFalse((ROOT/'.git').exists())
 def test_adult_hard_block_precedes_partial(self):
  s=self.text('safety/policy.py');self.assertLess(s.index("if adult >="),s.index("if partial_failure"))
 def test_total_failure_blocks(self):self.assertIn("total_failure: return Decision('BLOCK'",self.text('safety/policy.py'))
 def test_reels_allowed_only(self):self.assertIn("p.moderation_status='ALLOWED' AND p.is_safe=TRUE",self.text('services/social.py'))
 def test_review_row_lock(self):self.assertIn('FOR UPDATE',self.text('parent/routes.py'))
 def test_parent_ownership(self):self.assertIn("if not owns(session['user_id']",self.text('parent/routes.py'))
 def test_face_antispoof(self):self.assertIn('anti_spoofing=True',self.text('safety/face_service.py'))
 def test_whisper(self):self.assertIn('faster_whisper',self.text('safety/audio_service.py'))
 def test_four_modalities(self):
  s=self.text('database/schema.sql');[self.assertIn(x,s) for x in ["'IMAGE'","'VIDEO'","'AUDIO'","'TEXT'"]]
 def test_modes(self):
  s=self.text('auth/templates/mode_select.html');self.assertIn("t('kids_mode')",s);self.assertIn("t('parent_mode')",s)
 def test_reel_scroll_snap(self):self.assertIn('scroll-snap-type:y mandatory',self.text('static/css/littlenet.css'))
 def test_video_observer(self):self.assertIn('IntersectionObserver',self.text('static/js/littlenet.js'))
 def test_logout_post_only(self):self.assertIn("@auth_bp.route('/logout/',methods=['POST'])",self.text('auth/routes.py'))
 def test_switch_post_only(self):self.assertIn("@auth_bp.route('/switch-mode/',methods=['POST'])",self.text('auth/routes.py'))
 def test_screen_limit_bounds(self):self.assertIn('1<=mins<=1440',self.text('parent/routes.py'))
 def test_quiz_tamper_guard(self):self.assertIn('posted!=expected',self.text('quiz/routes.py'))
 def test_approved_only_chat(self):self.assertIn('can_interact',self.text('childMessage/routes.py'))
 def test_android_https(self):self.assertIn('usesCleartextTraffic="false"',self.text('android/app/src/main/AndroidManifest.xml'))
 def test_android_camera(self):self.assertIn('ACTION_IMAGE_CAPTURE',self.text('android/app/src/main/java/com/littlenet/app/MainActivity.java'))
 def test_schema_core_tables(self):
  s=self.text('database/schema.sql')
  for t in ['users','posts','comments','followers','child_messages','child_time_limits','child_usage_sessions','face_profiles','moderation_events','moderation_reviews','reports']:self.assertIn('CREATE TABLE IF NOT EXISTS '+t,s)

 def test_media_messages_exist(self):self.assertIn("/send-media/<int:child_id>/",self.text('childMessage/routes.py'))
 def test_video_audio_moderation(self):self.assertIn('_audio_from_video',self.text('safety/visual_service.py'));self.assertIn('check_audio(ap)',self.text('safety/visual_service.py'))
 def test_story_audio_moderation(self):self.assertIn('STORY_AUDIO_BLOCKED',self.text('uploadPost/routes.py'))
 def test_profile_picture_moderation(self):self.assertIn('/child/upload-profile-picture/',self.text('child/routes.py'));self.assertIn("evaluate(session['user_id'],'IMAGE',path)",self.text('child/routes.py'))
 def test_parent_content_approval(self):self.assertIn('/parent/content-approval/',self.text('parent/routes.py'))
 def test_recommended_approved_tags(self):self.assertIn('approved=TRUE',self.text('child/service.py'));self.assertIn('/recommended/',self.text('child/routes.py'))
 def test_behavior_indicator(self):self.assertIn('/parent/behavior/',self.text('parent/routes.py'))
 def test_live_safety(self):self.assertIn('/live-safety/',self.text('child/routes.py'))
 def test_heartbeat_api(self):self.assertIn('/api/usage/heartbeat/',self.text('child/routes.py'))
 def test_review_only_review_events(self):self.assertIn("decision='REVIEW' AND status='OPEN' FOR UPDATE",self.text('parent/routes.py'))
 def test_media_delivery_auth(self):self.assertIn("p['moderation_status']!='ALLOWED'",self.text('app.py'));self.assertIn("m['moderation_status']!='ALLOWED'",self.text('app.py'))
 def test_model_caching(self):self.assertIn('_CLIP=None',self.text('safety/visual_service.py'));self.assertIn('_MODEL=None',self.text('safety/audio_service.py'))
 def test_api_login_csrf_exempt(self):self.assertIn('@csrf.exempt',self.text('auth/api.py'))
 def test_login_rate_limit(self):self.assertIn("@limiter.limit('10 per minute')",self.text('auth/routes.py'))
 def test_global_kids_guard(self):self.assertIn('enforce_kids_controls',self.text('app.py'));self.assertIn("quiz_due(session['user_id'])",self.text('app.py'))


 def test_story_privacy_and_viewer(self):
  s=self.text('services/social.py');self.assertIn('following_child_id FROM followers',s);self.assertIn('approved=TRUE',s);self.assertIn('story_visible_to',s)
  self.assertIn("/stories/",self.text('child/routes.py'));self.assertIn("/api/story-view/<int:post_id>/",self.text('child/routes.py'))
  self.assertIn('scroll-snap-type:x mandatory',self.text('static/css/littlenet.css'));self.assertIn('data-story-id',self.text('child/templates/stories_viewer.html'))
 def test_request_form_never_assigned(self):
  for p in ROOT.rglob('*.py'):
   if '__pycache__' not in p.parts:self.assertNotRegex(p.read_text(),r'request\.form\s*=')
 def test_unique_template_basenames(self):
  seen={}
  for p in ROOT.rglob('templates/*.html'):
   self.assertNotIn(p.name,seen,f'duplicate template basename: {p.name} / {seen.get(p.name)}')
   seen[p.name]=str(p)
 def test_cross_midnight_usage_split(self):
  s=self.text('services/usage.py');self.assertIn('midnight=datetime.combine',s);self.assertIn("row['started_at'].date()<now.date()",s)
 def test_operator_tools_exist(self):
  for f in ['tools/create_admin.py','tools/model_warmup.py','tools/safety_check.py','tools/readiness.py']:self.assertTrue((ROOT/f).exists(),f)
 def test_detoxify_cached(self):self.assertIn('_DETOX=None',self.text('safety/text_service.py'));self.assertIn('_DETOX=Detoxify',self.text('safety/text_service.py'))


 def test_account_registration_transactions(self):
  s=self.text('auth/service.py');self.assertIn('conn=get_db_connection()',s);self.assertIn('conn.rollback()',s);self.assertIn('FOR UPDATE',s);self.assertIn("parent_id IS NULL",s)
 def test_suspended_accounts_cannot_login(self):self.assertIn("row['account_status']!='ACTIVE'",self.text('auth/service.py'))


 def test_profile_text_moderated_on_create_and_edit(self):
  s=self.text('child/routes.py');self.assertGreaterEqual(s.count("evaluate(session['user_id'],'TEXT',_public_profile_text(request.form))"),2);self.assertIn("if d.action!='ALLOW'",s)
 def test_identity_fields_validated(self):
  self.assertIn('validate_username',self.text('auth/service.py'));self.assertIn('ADULT_TERMS',self.text('services/identity.py'));self.assertIn('weak_password',self.text('auth/service.py'))
 def test_post_category_allowlist(self):
  s=self.text('uploadPost/routes.py');self.assertIn('from services.controls import SAFE_CATEGORIES',s);self.assertIn("category=category if category in SAFE_CATEGORIES else 'Other'",s)


 def test_chat_media_render_and_poll(self):
  t=self.text('childMessage/templates/chat.html');self.assertIn("m.message_type=='IMAGE'",t);self.assertIn("m.message_type=='VIDEO'",t);self.assertIn("m.message_type=='VOICE'",t);self.assertIn('message-status',t)
  j=self.text('static/js/chat.js');self.assertIn('/api/chat/${peer}/messages/',j);self.assertIn('setInterval(poll,2500)',j)
 def test_message_notifications(self):
  s=self.text('childMessage/routes.py');self.assertGreaterEqual(s.count("notify(child_id,'MESSAGE'"),3);self.assertIn('parent-reviewed message is now available',self.text('parent/routes.py'))


 def test_parent_review_has_protected_preview(self):
  t=self.text('parent/templates/safety_review.html');self.assertIn("t('inspect')",t);self.assertIn('e.preview.media_path',t)
  a=self.text('app.py');self.assertIn("role=='PARENT'",a);self.assertIn("m['moderation_status']!='REVIEW'",a)
 def test_parent_notifications_mark_read(self):self.assertIn('/parent/notifications/read/',self.text('parent/routes.py'))


 def test_parent_safety_selection_reflects_db(self):self.assertIn('c.safety.safety_level==level',self.text('parent/templates/parent_dashboard.html'));self.assertIn("k['safety']=fetch_one",self.text('parent/routes.py'))
 def test_profile_grid_supports_all_post_modalities(self):
  for f in ['child/templates/profile.html','child/templates/view_profile.html']:
   s=self.text(f);self.assertIn("p.media_type=='AUDIO'",s);self.assertIn('grid-text',s)
 def test_reports_validate_target(self):
  s=self.text('child/routes.py');self.assertIn("if not valid:return jsonify(error='target unavailable'),404",s);self.assertIn("kind=='MESSAGE'",s)
 def test_notifications_have_read_controls(self):self.assertIn('Mark all read',self.text('child/templates/notifications.html'));self.assertIn('Mark all read',self.text('parent/templates/parent_notifications.html'))


 def test_multi_story_upload_preserved(self):
  s=self.text('uploadPost/routes.py');self.assertIn("request.files.getlist('media')",s);self.assertIn('for file in files[:10]',s);self.assertIn('shutil.copy2',s)


 def test_document_messages_are_not_blindly_allowed(self):
  s=self.text('safety/document_service.py');self.assertIn('check_text',s);self.assertIn('check_image',s);self.assertIn('partial=True',s)
  r=self.text('childMessage/routes.py');self.assertIn('check_document(path,ext)',r);self.assertNotIn("'doc','docx'",r)
 def test_pdf_dependency_declared(self):self.assertIn('pypdf==',self.text('requirements-core.txt'))


 def test_share_and_report_controls_wired(self):
  p=self.text('templates/_post.html');self.assertIn('data-share-post',p);self.assertIn('data-report-post',p)
  r=self.text('uploadPost/templates/reels.html');self.assertIn('data-share-post',r);self.assertIn('data-report-post',r)
  j=self.text('static/js/littlenet.js');self.assertIn("fetch('/api/following/'",j);self.assertIn("fetch('/api/share-post/'",j);self.assertTrue("post('/report/'" in j or "postForm('/report/'" in j)


 def test_browser_forms_do_not_land_on_json(self):
  self.assertIn("redirect(f'/post/{post_id}/')",self.text('uploadPost/routes.py'))
  self.assertIn('data-safe-upload',self.text('uploadPost/templates/upload_post.html'));j=self.text('static/js/littlenet.js');self.assertIn("'/upload-story/'",j);self.assertIn("'/child/upload-post/'",j)
  self.assertIn('data-profile-photo',self.text('child/templates/profile.html'));self.assertIn('data-media-form',self.text('childMessage/templates/chat.html'));self.assertIn('new FormData(form)',self.text('static/js/chat.js'))

 def test_promoted_admin_dashboard_is_detailed(self):
  s=self.text('admin/routes.py');self.assertIn('/admin/users/',s);self.assertIn('/admin/reports/',s);self.assertIn('/admin/moderation/',s);self.assertIn('/admin/audit/',s);self.assertIn('admin_audit_logs',self.text('database/schema.sql'))

 def test_live_moderation_is_continuous_and_fail_closed(self):
  s=self.text('child/routes.py');self.assertIn('/api/live-safety/check/',s);self.assertIn("LIVE_SAFETY_",s);self.assertIn("decision='BLOCK'",s)
  j=self.text('static/js/live_safety.js');self.assertIn('getUserMedia',j);self.assertIn('setInterval(check,1600)',j)

 def test_behavior_analysis_has_explainable_metrics_and_trend(self):
  s=self.text('services/behavior.py');self.assertIn('adult_blocks',s);self.assertIn('weapon_blocks',s);self.assertIn('harmful_text_blocks',s);self.assertIn("trend =",s)

 def test_screen_time_generates_one_time_parent_alerts(self):
  s=self.text('services/usage.py');self.assertIn('SCREEN_TIME_WARNING',s);self.assertIn('SCREEN_TIME_LIMIT_REACHED',s);self.assertIn('parent_notifications',s)

if __name__=='__main__':unittest.main()


def test_release_automation_files_exist():
    root = Path(__file__).resolve().parents[1]
    required = [
        root / '.github/workflows/ci.yml',
        root / '.github/workflows/build-apk.yml',
        root / 'android/gradle/wrapper/gradle-wrapper.properties',
        root / '.gitignore',
    ]
    assert all(p.exists() for p in required)


def test_apk_workflow_requires_https_backend_and_builds_debug_apk():
    root = Path(__file__).resolve().parents[1]
    text = (root / '.github/workflows/build-apk.yml').read_text(encoding='utf-8')
    assert 'BACKEND_URL must be a real HTTPS URL' in text
    assert ':app:assembleDebug' in text
    assert 'app-debug.apk' in text


def test_split_ai_runtime_files_exist():
    root = Path(__file__).resolve().parents[1]
    for rel in ['Dockerfile.web','Dockerfile.ai','ai_server.py','safety/remote_client.py']:
        assert (root / rel).exists(), rel


def test_railway_defaults_to_lightweight_web_container():
    root = Path(__file__).resolve().parents[1]
    railway = (root/'railway.toml').read_text(encoding='utf-8')
    assert 'Dockerfile.web' in railway
    core = (root/'requirements-core.txt').read_text(encoding='utf-8')
    assert 'torch' not in core.lower()
    assert 'tensorflow' not in core.lower()
    assert 'opencv-python-headless' not in core.lower()


def test_remote_ai_failures_fail_closed():
    root = Path(__file__).resolve().parents[1]
    for rel in ['safety/text_service.py','safety/audio_service.py','safety/visual_service.py']:
        text=(root/rel).read_text(encoding='utf-8')
        assert 'remote_ai_unavailable' in text
        assert 'total_safety_failure' in text


def test_health_and_readiness_endpoints_are_separate():
    root = Path(__file__).resolve().parents[1]
    app=(root/'app.py').read_text(encoding='utf-8')
    assert "@app.route('/healthz')" in app
    assert "@app.route('/readyz')" in app
    assert "ai_mode" in app


def test_release_packager_excludes_secrets_and_user_media():
    root = Path(__file__).resolve().parents[1]
    text=(root/'tools/package_release.py').read_text(encoding='utf-8')
    assert "'.env'" in text
    assert "'uploads'" in text
    assert "'.git'" in text


def test_modal_ai_deployment_is_gpu_cached_and_scales_to_zero():
    root = Path(__file__).resolve().parents[1]
    text = (root / 'modal_ai.py').read_text(encoding='utf-8')
    assert 'gpu="T4"' in text
    assert 'littlenet-model-cache' in text
    assert 'min_containers=0' in text
    assert 'scaledown_window=300' in text
    assert '@modal.wsgi_app()' in text
    assert 'warm_models' in text


def test_modal_web_deployment_persists_uploads_and_uses_external_db():
    root = Path(__file__).resolve().parents[1]
    text = (root / 'modal_web.py').read_text(encoding='utf-8')
    assert 'littlenet-uploads' in text
    assert 'DATABASE_URL' in text
    assert 'uploads.commit()' in text
    assert 'max_containers=1' in text
    assert '@modal.wsgi_app()' in text
    assert 'init_database' in text


def test_gpu_aware_inference_keeps_cpu_fallback():
    root = Path(__file__).resolve().parents[1]
    visual = (root/'safety/visual_service.py').read_text(encoding='utf-8')
    audio = (root/'safety/audio_service.py').read_text(encoding='utf-8')
    assert 'LITTLENET_DEVICE' in visual and "return 'cuda' if torch.cuda.is_available() else 'cpu'" in visual
    assert "device=0 if _runtime_device()=='cuda' else -1" in visual
    assert 'LITTLENET_DEVICE' in audio and "compute_type='float16' if device=='cuda' else 'int8'" in audio


def test_modal_deployment_docs_cover_secrets_warmup_and_external_postgres():
    root = Path(__file__).resolve().parents[1]
    text = (root/'MODAL_DEPLOYMENT.md').read_text(encoding='utf-8')
    assert 'modal secret create littlenet-ai-secrets' in text
    assert 'modal run modal_ai.py' in text
    assert 'modal deploy modal_ai.py' in text
    assert 'PostgreSQL' in text
    assert 'modal_web.py' in text


def test_ai_http_service_requires_shared_secret_fail_closed():
    root = Path(__file__).resolve().parents[1]
    text = (root/'ai_server.py').read_text(encoding='utf-8')
    assert 'hmac.compare_digest' in text
    assert 'return bool(secret)' in text
    assert 'return not secret' not in text


def test_modal_github_deploy_is_manual_and_uses_modal_tokens():
    root = Path(__file__).resolve().parents[1]
    text = (root/'.github/workflows/deploy-modal.yml').read_text(encoding='utf-8')
    assert 'workflow_dispatch:' in text
    assert 'MODAL_TOKEN_ID' in text and 'MODAL_TOKEN_SECRET' in text
    assert 'modal deploy modal_ai.py' in text
    assert 'modal deploy modal_web.py' in text


def test_smart_parent_controls_are_persistent_and_server_enforced():
    root=Path(__file__).resolve().parents[1]
    schema=(root/'database/schema.sql').read_text(encoding='utf-8')
    controls=(root/'services/controls.py').read_text(encoding='utf-8')
    app=(root/'app.py').read_text(encoding='utf-8')
    parent=(root/'parent/routes.py').read_text(encoding='utf-8')
    assert 'CREATE TABLE IF NOT EXISTS parent_control_settings' in schema
    for name in ['allow_reels','allow_stories','allow_messaging','allow_posting','allow_discover','educational_only_feed']:
        assert name in schema and name in controls
    assert "feature_allowed(session['user_id'],feature)" in app
    assert "/parent/controls/" in parent


def test_personalized_feed_has_parent_categories_following_and_age_targeting():
    root=Path(__file__).resolve().parents[1]
    social=(root/'services/social.py').read_text(encoding='utf-8')
    child=(root/'child/service.py').read_text(encoding='utf-8')
    schema=(root/'database/schema.sql').read_text(encoding='utf-8')
    assert 'audience_age_group' in schema
    assert 'p.content_category = ANY(%s)' in social
    assert "following_child_id FROM followers" in social
    assert "p.audience_age_group='ALL'" in social
    recommendation=(root/'services/recommendation.py').read_text(encoding='utf-8')
    assert 'effective_categories(cid)' in recommendation
    assert "p.moderation_status='ALLOWED' AND p.is_safe=TRUE" in recommendation


def test_multilingual_interface_preferences_exist():
    root=Path(__file__).resolve().parents[1]
    schema=(root/'database/schema.sql').read_text(encoding='utf-8')
    i18n=(root/'services/i18n.py').read_text(encoding='utf-8')
    auth=(root/'auth/routes.py').read_text(encoding='utf-8')
    assert 'CREATE TABLE IF NOT EXISTS user_preferences' in schema
    assert "'EN':'English'" in i18n and "'KN':'ಕನ್ನಡ'" in i18n and "'HI':'हिन्दी'" in i18n
    assert "@auth_bp.route('/language/'" in auth


def test_security_headers_cover_privacy_baseline():
    root=Path(__file__).resolve().parents[1]
    app=(root/'app.py').read_text(encoding='utf-8')
    for header in ['Content-Security-Policy','Permissions-Policy','Strict-Transport-Security','X-Content-Type-Options','Referrer-Policy']:
        assert header in app


def test_existing_database_upgrade_covers_new_future_enhancements():
    root=Path(__file__).resolve().parents[1]
    text=(root/'database/upgrade.sql').read_text(encoding='utf-8')
    assert 'ADD COLUMN IF NOT EXISTS audience_age_group' in text
    assert 'CREATE TABLE IF NOT EXISTS parent_control_settings' in text
    assert 'CREATE TABLE IF NOT EXISTS user_preferences' in text


def test_parent_first_workflow_matches_latest_ppt():
    root=Path(__file__).resolve().parents[1]
    auth=(root/'auth/routes.py').read_text(encoding='utf-8')
    service=(root/'auth/service.py').read_text(encoding='utf-8')
    parent=(root/'parent/routes.py').read_text(encoding='utf-8')
    assert "@auth_bp.route('/register-parent'," in auth
    assert 'register_parent_direct' in service
    assert 'create_child_by_parent' in service
    assert "/parent/create-child/" in parent
    assert "'ACCOUNT_CREATED_BY_PARENT'" in service
    assert "account_status)\n          VALUES(%s,%s,%s,%s,'CHILD',%s,'ACTIVE')" in service


def test_learning_challenges_and_educational_reels_are_real_features():
    root=Path(__file__).resolve().parents[1]
    schema=(root/'database/schema.sql').read_text(encoding='utf-8')
    routes=(root/'quiz/routes.py').read_text(encoding='utf-8')
    reels=(root/'uploadPost/templates/reels.html').read_text(encoding='utf-8')
    assert 'CREATE TABLE IF NOT EXISTS learning_challenges' in schema
    assert 'CREATE TABLE IF NOT EXISTS learning_challenge_attempts' in schema
    assert "@quiz_bp.route('/learning/')" in routes
    assert "@quiz_bp.route('/parent/learning-report/')" in routes
    assert "t('educational_reel')" in reels


def test_save_bookmark_and_saved_collection_are_wired():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'uploadPost/routes.py').read_text(encoding='utf-8')
    js=(root/'static/js/littlenet.js').read_text(encoding='utf-8')
    post=(root/'templates/_post.html').read_text(encoding='utf-8')
    reels=(root/'uploadPost/templates/reels.html').read_text(encoding='utf-8')
    assert "@upload_bp.route('/save/<int:post_id>/'" in routes
    assert "@upload_bp.route('/saved/')" in routes
    assert 'data-save-post' in post and 'data-save-post' in reels
    assert 'function bindSave' in js


def test_mute_has_visible_profile_control():
    root=Path(__file__).resolve().parents[1]
    profile=(root/'child/templates/view_profile.html').read_text(encoding='utf-8')
    assert 'action="/mute/{{target_user_id}}/"' in profile


def test_init_db_always_applies_idempotent_upgrade_sql():
    root=Path(__file__).resolve().parents[1]
    init=(root/'tools/init_db.py').read_text(encoding='utf-8')
    assert "database/upgrade.sql" in init


def test_parent_category_controls_apply_to_profile_grids_too():
    root=Path(__file__).resolve().parents[1]
    social=(root/'services/social.py').read_text(encoding='utf-8')
    child=(root/'child/routes.py').read_text(encoding='utf-8')
    assert 'def visible_profile_posts' in social
    assert "post_visible_to(viewer_id,p['post_id'])" in social
    assert child.count('visible_profile_posts(')>=2


def test_parent_created_child_profile_text_is_moderated():
    root=Path(__file__).resolve().parents[1]
    parent=(root/'parent/routes.py').read_text(encoding='utf-8')
    assert "signals=check_text(public_text)" in parent
    assert "decision=decide(signals,'STRICT')" in parent
    assert "decision.action!='ALLOW'" in parent


def test_cyberbullying_and_weapon_redundancy_are_explicit():
    root=Path(__file__).resolve().parents[1]
    text=(root/'safety/text_service.py').read_text(encoding='utf-8')
    visual=(root/'safety/visual_service.py').read_text(encoding='utf-8')
    assert 'BULLYING_TERMS' in text and "'CYBERBULLYING'" in text
    assert "'partial_safety_failure':bool(text) and bool(errors)" in text
    assert "'total_safety_failure':bool(text) and ran==0" in text
    assert 'weapon gun knife dangerous object' in visual
    assert "c.get('weapon',0)" in visual


def test_templates_are_csp_compatible_no_inline_event_handlers():
    root=Path(__file__).resolve().parents[1]
    pattern=re.compile(r"\son[a-z]+\s*=",re.I)
    offenders=[]
    for template in root.rglob("*.html"):
        if pattern.search(template.read_text(encoding="utf-8")):
            offenders.append(str(template.relative_to(root)))
    assert offenders==[], f"inline event handlers violate CSP: {offenders}"

def test_android_backend_placeholder_is_only_runtime_placeholder():
    root=Path(__file__).resolve().parents[1]
    strings=(root/"android/app/src/main/res/values/strings.xml").read_text(encoding="utf-8")
    assert "https://YOUR-LITTLENET-BACKEND.example.com/" in strings
    setter=(root/"tools/set_backend_url.py").read_text(encoding="utf-8")
    assert "https://" in setter and "backend_url" in setter


def test_parent_safety_alerts_update_live_in_parent_mode():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'parent/routes.py').read_text(encoding='utf-8')
    base=(root/'parent/templates/parent_base.html').read_text(encoding='utf-8')
    js=(root/'static/js/littlenet.js').read_text(encoding='utf-8')
    assert "/api/parent/notifications/unread/" in routes
    assert 'data-parent-alert-count' in base
    assert 'pollParentAlerts' in js and 'setInterval(pollParentAlerts,10000)' in js


def test_for_you_feed_has_ai_semantic_ranking_with_safe_fallback():
    root=Path(__file__).resolve().parents[1]
    rec=(root/'services/recommendation.py').read_text(encoding='utf-8')
    semantic=(root/'safety/semantic_service.py').read_text(encoding='utf-8')
    server=(root/'ai_server.py').read_text(encoding='utf-8')
    child=(root/'child/service.py').read_text(encoding='utf-8')
    assert 'remote_client.rank_texts' in rec
    assert 'rank_texts(profile_text' in semantic and 'get_text_features' in semantic
    assert '/ai/rank' in server
    assert 'personalized_posts' in child
    assert "p.moderation_status='ALLOWED' AND p.is_safe=TRUE" in rec


def test_multilingual_core_workflows_use_translation_keys():
    root=Path(__file__).resolve().parents[1]
    i18n=(root/'services/i18n.py').read_text(encoding='utf-8')
    for key in ['tagline','kids_mode','login','search_students','live_safety','children','safety_intro','complete_challenge','publish']:
        assert f"'{key}'" in i18n
    for rel in ['auth/templates/mode_select.html','auth/templates/login.html','child/templates/profile.html','parent/templates/parent_dashboard.html','parent/templates/safety_review.html','quiz/templates/learning.html']:
        assert "t('" in (root/rel).read_text(encoding='utf-8')
    reels=(root/'uploadPost/templates/reels.html').read_text(encoding='utf-8')
    js=(root/'static/js/littlenet.js').read_text(encoding='utf-8')
    assert 'data-label-educational' in reels and 'dataset.labelEducational' in js


def test_route_auditor_covers_api_blueprints():
    root=Path(__file__).resolve().parents[1]
    audit=(root/'tools/audit_routes.py').read_text(encoding='utf-8')
    assert "rglob('api.py')" in audit
    assert "'auth/api.py':{'api_login'}" in audit
    parent=(root/'parent/api.py').read_text(encoding='utf-8')
    assert parent.count('@parent_required')>=3

def test_release_verifier_exists_and_allows_only_env_example():
    root=Path(__file__).resolve().parents[1]
    v=(root/'tools/verify_release.py').read_text(encoding='utf-8')
    assert "forbidden_names={'.env','local.properties'}" in v
    assert "'.env.example'" in v


def test_email_child_approval_requires_explicit_post_confirmation():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'auth/routes.py').read_text(encoding='utf-8')
    confirm=(root/'auth/templates/approve_confirm.html').read_text(encoding='utf-8')
    assert "@auth_bp.route('/approve/<token>/',methods=['GET','POST'])" in routes
    assert "if request.method=='GET':return render_template('approve_confirm.html'" in routes
    assert 'csrf_token' in confirm and '<form method="post">' in confirm

def test_token_parent_setup_requires_eight_char_password_and_rate_limit():
    root=Path(__file__).resolve().parents[1]
    service=(root/'auth/service.py').read_text(encoding='utf-8')
    routes=(root/'auth/routes.py').read_text(encoding='utf-8')
    template=(root/'auth/templates/parent_register.html').read_text(encoding='utf-8')
    assert "if len(password)<8:return False,'weak_password'" in service
    assert "@auth_bp.route('/register-parent/<token>/'" in routes and "@limiter.limit('10 per minute')" in routes
    assert 'minlength="8"' in template

def test_hosted_runtime_enforces_secure_secret_and_proxy_https():
    root=Path(__file__).resolve().parents[1]
    app=(root/'app.py').read_text(encoding='utf-8')
    config=(root/'config.py').read_text(encoding='utf-8')
    assert 'ProxyFix' in app and 'x_proto=1' in app
    assert "len(Config.SECRET_KEY)<32" in app
    assert "AI_SHARED_SECRET is required" in app
    assert 'BASE_URL.startswith("https://")' in config


def test_quiet_hours_are_server_enforced_and_persisted():
    root=Path(__file__).resolve().parents[1]
    schema=(root/'database/schema.sql').read_text(encoding='utf-8')
    controls=(root/'services/controls.py').read_text(encoding='utf-8')
    app=(root/'app.py').read_text(encoding='utf-8')
    template=(root/'parent/templates/parent_controls.html').read_text(encoding='utf-8')
    assert 'quiet_hours_enabled BOOLEAN' in schema and 'quiet_start TIME' in schema and 'quiet_end TIME' in schema
    assert 'def quiet_hours_state' in controls and 'APP_TIMEZONE' in controls
    assert "if quiet['active']" in app and "render_template('quiet_hours.html'" in app
    assert 'name="quiet_start"' in template and 'name="quiet_end"' in template


def test_quiet_hours_runtime_handles_overnight_window(monkeypatch):
    from datetime import datetime
    import services.controls as c
    monkeypatch.setattr(c,'controls_for_child',lambda _:{'quiet_hours_enabled':True,'quiet_start':'21:00','quiet_end':'07:00'})
    assert c.quiet_hours_state(1,datetime(2026,1,1,22,0))['active'] is True
    assert c.quiet_hours_state(1,datetime(2026,1,2,6,30))['active'] is True
    assert c.quiet_hours_state(1,datetime(2026,1,2,12,0))['active'] is False


def test_parent_home_has_real_presence_behavior_and_quiz_metrics():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'parent/routes.py').read_text(encoding='utf-8')
    template=(root/'parent/templates/parent_dashboard.html').read_text(encoding='utf-8')
    usage=(root/'services/usage.py').read_text(encoding='utf-8')
    assert 'def online_state' in usage
    assert "k['presence']=online_state(cid)" in routes
    assert "k['behavior']=behavior_summary(cid)" in routes
    assert "k['quiz_7d']" in routes
    assert '7-day behaviour' in template and 'Quiz 7d' in template and 'Online now' in template


def test_discover_is_not_a_global_child_directory():
    root=Path(__file__).resolve().parents[1]
    service=(root/'child/service.py').read_text(encoding='utf-8')
    template=(root/'child/templates/discover.html').read_text(encoding='utf-8')
    assert 'approved_friends AS' in service and 'network AS' in service
    assert "LOWER(cp.school_name)" in service and "pcm.parent_id" in service
    assert 'ORDER BY RANDOM()' not in service
    assert 'recommendation_reason' in template


def test_comments_and_likes_require_approved_connections():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'uploadPost/routes.py').read_text(encoding='utf-8')
    assert routes.count("approved connection required")>=2
    assert 'not can_interact' in routes
    social=(root/'services/social.py').read_text(encoding='utf-8')
    assert "p.child_id=%s OR p.child_id IN (SELECT following_child_id" in social


def test_block_review_alerts_have_email_and_in_app_paths():
    root=Path(__file__).resolve().parents[1]
    social=(root/'services/social.py').read_text(encoding='utf-8')
    assert 'INSERT INTO parent_notifications' in social
    assert "'BLOCK' in str(kind).upper()" in social and "'REVIEW' in str(kind).upper()" in social
    assert "send_email(parent['email'],'LittleNet safety alert'" in social


def test_admin_can_remove_post_but_not_unblock_hard_block():
    root=Path(__file__).resolve().parents[1]
    routes=(root/'admin/routes.py').read_text(encoding='utf-8')
    template=(root/'admin/templates/admin_moderation.html').read_text(encoding='utf-8')
    assert "@admin_bp.route('/admin/post/<int:post_id>/remove/'" in routes
    assert "moderation_status='BLOCKED',is_safe=FALSE" in routes
    assert 'Remove post' in template
