import os
import re

PATTERNS = [
    (r'(?i)AIzaSy[A-Za-z0-9_-]{33}', 'Google/Gemini API Key'),
    (r'(?i)sk-[A-Za-z0-9]{20,}', 'OpenAI/K2 Secret Key'),
    (r'(?i)bearer\s+[A-Za-z0-9_.-]{20,}', 'Bearer Token'),
    (r'(?i)ghp_[A-Za-z0-9]{36}', 'GitHub Token'),
    (r'postgres(?:ql)?://[a-zA-Z0-9_\-]+:[^@\s]+@[a-zA-Z0-9_\-\.]+:[0-9]+/[a-zA-Z0-9_\-]+', 'Postgres URL with Password'),
]

root = '.'
ignore_dirs = {'.git', 'node_modules', '.venv', '__pycache__', '.idea', '.vscode'}
findings = []

for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = [d for d in dirnames if d not in ignore_dirs]
    for fname in filenames:
        if fname.endswith(('.pyc', '.apk', '.png', '.jpg', '.webp', '.zip', '.jar', '.log', '.db')):
            continue
        fpath = os.path.join(dirpath, fname)
        try:
            with open(fpath, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                for pat, label in PATTERNS:
                    matches = re.findall(pat, content)
                    for m in matches:
                        # Mask finding
                        if len(m) > 10:
                            masked = m[:4] + '...' + m[-4:]
                        else:
                            masked = '***'
                        findings.append((fpath, label, masked))
        except Exception as e:
            pass

print(f'TOTAL FINDINGS: {len(findings)}')
for f, l, m in findings:
    print(f'{f}: {l} -> {m}')
