import subprocess,sys,shutil
from pathlib import Path
R=Path(__file__).parents[1]
steps=[
 [sys.executable,'-m','pytest','-q'],
 [sys.executable,'tools/preflight.py'],
 [sys.executable,'tools/audit_routes.py'],
 [sys.executable,'tools/audit_templates.py'],
 [sys.executable,'tools/readiness.py'],
 [sys.executable,'tools/scope_check.py'],
]
for cmd in steps:
    print('\n==>', ' '.join(cmd));r=subprocess.run(cmd,cwd=R)
    if r.returncode:raise SystemExit(r.returncode)
if shutil.which('node'):
    for rel in ['static/js/littlenet.js','static/js/live_safety.js','static/js/chat.js','static/js/stories.js']:
        print('\n==> node --check',rel);r=subprocess.run(['node','--check',rel],cwd=R)
        if r.returncode:raise SystemExit(r.returncode)
import xml.etree.ElementTree as ET
for p in (R/'android/app/src/main/res').rglob('*.xml'):ET.parse(p)
ET.parse(R/'android/app/src/main/AndroidManifest.xml')
print('\nANDROID XML: PASS')
print('\nALL LOCAL SOURCE AUDITS PASSED')
