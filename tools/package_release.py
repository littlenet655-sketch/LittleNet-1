"""Create a clean ZIP suitable for private GitHub upload or handoff."""
from pathlib import Path
import shutil, zipfile

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT.parent/'LittleNet-complete-release.zip'
EXCLUDE_DIRS={'.git','.pytest_cache','__pycache__','.venv','venv','uploads','models','model_cache','.gradle','build'}
EXCLUDE_FILES={'.env','local.properties'}
EXCLUDE_SUFFIXES={'.pyc','.pyo','.jks','.keystore'}

if OUT.exists():OUT.unlink()
with zipfile.ZipFile(OUT,'w',zipfile.ZIP_DEFLATED) as z:
    for p in ROOT.rglob('*'):
        rel=p.relative_to(ROOT)
        if p.is_dir():continue
        if any(part in EXCLUDE_DIRS for part in rel.parts):continue
        if p.name in EXCLUDE_FILES or p.suffix in EXCLUDE_SUFFIXES:continue
        z.write(p,rel.as_posix())
print(OUT)
