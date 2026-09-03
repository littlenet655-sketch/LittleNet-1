from pathlib import Path
import ast,re,sys
root=Path(__file__).parents[1];fail=[]
for p in root.rglob('*.py'):
 if '__pycache__' in p.parts:continue
 try:ast.parse(p.read_text(encoding='utf-8'))
 except Exception as e:fail.append(f'PY {p.relative_to(root)}: {e}')
schema=(root/'database/schema.sql').read_text()
for table in ['users','parent_child_map','posts','likes','comments','followers','child_messages','notifications','child_time_limits','child_usage_sessions','quizzes','face_profiles','moderation_events','moderation_reviews','reports','blocked_users','muted_users']:
 if f'CREATE TABLE IF NOT EXISTS {table}' not in schema:fail.append('SCHEMA '+table)
if (root/'.git').exists():fail.append('Git metadata must not exist in local export')
print('PREFLIGHT:', 'PASS' if not fail else 'FAIL');[print('-',x) for x in fail];sys.exit(bool(fail))
