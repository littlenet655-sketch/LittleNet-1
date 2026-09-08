import subprocess,sys,shutil
from pathlib import Path
R=Path(__file__).parents[1]
steps=[
 [sys.executable,'-m','pytest','-q'],
 [sys.executable,'tools/preflight.py'],
 [sys.executable,'tools/audit_routes.py'],
 [sys.executable,'tools/audit_templates.py'],
 [sys.executable,'tools/readiness.py','--source-only'],
 [sys.executable,'tools/scope_check.py'],
]
for cmd in steps:
    print('\n==>', ' '.join(cmd));r=subprocess.run(cmd,cwd=R)
    if r.returncode:raise SystemExit(r.returncode)
if shutil.which('node'):
    for rel in ['static/js/littlenet.js','static/js/live_safety.js','static/js/chat.js','static/js/stories.js']:
        print('\n==> node --check',rel);r=subprocess.run(['node','--check',rel],cwd=R)
        if r.returncode:raise SystemExit(r.returncode)

# Android is now generated from the native Flutter project in its dedicated CI.
# Source audit therefore verifies the checked-in native client and rejects any
# return of the retired WebView architecture.
flutter_root=R/'mobile_flutter'
main=flutter_root/'lib/main.dart'
pubspec=flutter_root/'pubspec.yaml'
prepare=flutter_root/'tool/prepare_android.sh'
for p in (main,pubspec,prepare):
    if not p.is_file():raise SystemExit(f'Missing native Flutter source: {p.relative_to(R)}')
if 'LittleNetApp' not in main.read_text(encoding='utf-8'):
    raise SystemExit('Native Flutter LittleNetApp entrypoint missing')
if 'com.littlenet.app' not in prepare.read_text(encoding='utf-8'):
    raise SystemExit('Native Android package contract missing')
for p in flutter_root.rglob('*'):
    if not p.is_file() or p.suffix not in {'.dart','.yaml','.yml','.kt','.java'}:
        continue
    text=p.read_text(encoding='utf-8',errors='ignore').lower()
    if any(term in text for term in ('webview_flutter','inappwebview','android.webkit.webview','webviewclient')):
        raise SystemExit(f'WebView regression found in native client: {p.relative_to(R)}')
print('\nNATIVE FLUTTER ANDROID SOURCE: PASS')
print('\nALL LOCAL SOURCE AUDITS PASSED')
