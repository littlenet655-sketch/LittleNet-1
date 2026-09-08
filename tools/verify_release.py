"""Verify that the sanitized handoff ZIP contains the native LittleNet release source only."""
from pathlib import Path
import sys,zipfile

ROOT=Path(__file__).resolve().parents[1]
ZIP=ROOT.parent/'LittleNet-complete-release.zip'
if not ZIP.exists():
    raise SystemExit('Release ZIP not found; run tools/package_release.py first')

forbidden_names={'.env','local.properties'}
forbidden_parts={'.git','.pytest_cache','__pycache__','.venv','venv','uploads','models','model_cache','.gradle','build'}
forbidden_suffixes={'.pyc','.pyo','.jks','.keystore'}
required=[
    'README.md',
    'BUILD_STATUS.md',
    'SCOPE_STATUS.md',
    '.env.example',
    'app.py',
    'modal_ai.py',
    'modal_web.py',
    'mobile/api.py',
    'mobile/admin_api.py',
    'mobile_flutter/pubspec.yaml',
    'mobile_flutter/lib/main.dart',
    'mobile_flutter/tool/prepare_android.sh',
    '.github/workflows/flutter-native.yml',
    '.github/workflows/release-android.yml',
    '.github/workflows/deploy-modal.yml',
]
errors=[]
with zipfile.ZipFile(ZIP) as z:
    names=z.namelist()
    for name in names:
        p=Path(name)
        if p.name in forbidden_names:
            errors.append(f'forbidden file: {name}')
        if any(part in forbidden_parts for part in p.parts):
            errors.append(f'forbidden runtime path: {name}')
        if p.suffix in forbidden_suffixes:
            errors.append(f'forbidden sensitive/build suffix: {name}')
    for name in required:
        if name not in names:
            errors.append(f'missing release file: {name}')

    # The submission source must not silently reintroduce the retired WebView
    # client. The Flutter build workflow performs the same check at APK time.
    for name in names:
        if not name.endswith(('.dart','.yaml','.yml','.kt','.java','.py','.sh')):
            continue
        try:
            text=z.read(name).decode('utf-8',errors='ignore').lower()
        except Exception:
            continue
        if name.startswith('mobile_flutter/') and any(term in text for term in (
            'webview_flutter','inappwebview','android.webkit.webview','webviewclient'
        )):
            errors.append(f'webview regression in native release source: {name}')

print('RELEASE_FILES',len(names),'ERRORS',len(errors))
[print('-',e) for e in errors]
sys.exit(bool(errors))
