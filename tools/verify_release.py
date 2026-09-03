"""Verify that the sanitized handoff ZIP does not contain local secrets or runtime data."""
from pathlib import Path
import sys,zipfile
ROOT=Path(__file__).resolve().parents[1]
ZIP=ROOT.parent/'LittleNet-complete-release.zip'
if not ZIP.exists():raise SystemExit('Release ZIP not found; run tools/package_release.py first')
forbidden_names={'.env','local.properties'}
forbidden_parts={'.git','.pytest_cache','__pycache__','.venv','venv','uploads','models','model_cache','.gradle','build'}
forbidden_suffixes={'.pyc','.pyo','.jks','.keystore'}
errors=[]
with zipfile.ZipFile(ZIP) as z:
    names=z.namelist()
    for name in names:
        p=Path(name)
        if p.name in forbidden_names:errors.append(f'forbidden file: {name}')
        if any(part in forbidden_parts for part in p.parts):errors.append(f'forbidden runtime path: {name}')
        if p.suffix in forbidden_suffixes:errors.append(f'forbidden sensitive/build suffix: {name}')
    required=['README.md','BUILD_STATUS.md','SCOPE_STATUS.md','.env.example','app.py','modal_ai.py','android/app/src/main/AndroidManifest.xml','.github/workflows/build-apk.yml']
    for name in required:
        if name not in names:errors.append(f'missing release file: {name}')
print('RELEASE_FILES',len(names),'ERRORS',len(errors));[print('-',e) for e in errors];sys.exit(bool(errors))
