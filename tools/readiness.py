from pathlib import Path
import ast,shutil,os
R=Path(__file__).parents[1]
checks=[]
def add(name,ok,detail=''):checks.append((name,bool(ok),detail))

bad=[]
for p in R.rglob('*.py'):
    if '__pycache__' in p.parts:continue
    try:ast.parse(p.read_text(encoding='utf-8'))
    except Exception as e:bad.append(f'{p.relative_to(R)}:{e}')
add('Python source parses',not bad,'; '.join(bad))
add('No Git metadata',not (R/'.git').exists())
for rel in [
 'safety/visual_service.py','safety/audio_service.py','safety/face_service.py','safety/document_service.py',
 'services/behavior.py','admin/templates/admin_dashboard.html','admin/templates/admin_moderation.html',
 'child/templates/live_safety.html','static/js/live_safety.js','uploadPost/templates/reels.html',
 'child/templates/stories_viewer.html','parent/templates/safety_review.html','Dockerfile','Dockerfile.web','Dockerfile.ai','ai_server.py','safety/remote_client.py','railway.toml','docker-entrypoint.sh','DEPLOYMENT_FREE.md','.github/workflows/ci.yml','.github/workflows/build-apk.yml',
 'modal_ai.py','modal_web.py','MODAL_DEPLOYMENT.md','requirements-modal.txt','.github/workflows/deploy-modal.yml',
 'android/app/src/main/java/com/littlenet/app/MainActivity.java'
]:add(rel,(R/rel).exists())
add('Backend URL configured','YOUR-LITTLENET-BACKEND' not in (R/'android/app/src/main/res/values/strings.xml').read_text(),'requires final hosted HTTPS backend')
add('Gradle available',bool(shutil.which('gradle') or (R/'tools/gradle-8.9/gradle-8.9/bin/gradle.bat').exists()),'Android Studio/Gradle needed for APK binary')
add('Android SDK configured',bool(os.environ.get('ANDROID_HOME') or os.environ.get('ANDROID_SDK_ROOT') or (Path.home()/'AppData/Local/Android/sdk').exists()),'Android SDK needed for APK binary')
add('APK binary compiled', (R/'LittleNet-v1.0-submission.apk').exists() or (R/'android/app/build/outputs/apk/debug/app-debug.apk').exists(), 'Installable Android APK')
print('LittleNet readiness')
for n,ok,d in checks:print(('PASS' if ok else 'WAIT').ljust(5),n,('- '+d) if d else '')
external={'Backend URL configured','Gradle available','Android SDK configured','No Git metadata'}
source_ready=all(ok for n,ok,d in checks if n not in external)
apk_ready=(R/'LittleNet-v1.0-submission.apk').exists() or (R/'android/app/build/outputs/apk/debug/app-debug.apk').exists()
print('\nSOURCE_READY=',source_ready)
print('APK_BINARY_READY=',apk_ready)
raise SystemExit(0 if (source_ready and apk_ready) else 1)
