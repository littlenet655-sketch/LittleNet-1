import os
import re
import json

flutter_dir = "mobile_flutter/lib"
screens = {}

api_calls = set()
with open("mobile_flutter/lib/api.dart", "r", encoding="utf-8") as f:
    api_content = f.read()

# find method signatures in api.dart
api_methods = re.findall(r'Future<[^>]+>\s+([a-zA-Z0-9_]+)\s*\(', api_content)
print(f"API methods in api.dart: {len(api_methods)}")

for root, dirs, files in os.walk(flutter_dir):
    for f in files:
        if f.endswith('.dart'):
            p = os.path.join(root, f)
            with open(p, 'r', encoding='utf-8') as df:
                content = df.read()
            
            # find widgets
            classes = re.findall(r'class\s+([a-zA-Z0-9_]+)\s+extends\s+(StatefulWidget|StatelessWidget)', content)
            
            # find api calls
            called = [m for m in api_methods if f"api.{m}" in content or f"{m}(" in content]
            
            screens[p.replace('\\', '/')] = {
                "widgets": [c[0] for c in classes],
                "api_methods_used": called,
                "lines": len(content.splitlines()),
                "size_bytes": len(content)
            }

with open("audit/flutter_screen_inventory.json", "w", encoding="utf-8") as out:
    json.dump(screens, out, indent=2)

print(f"Inventoried {len(screens)} dart files.")
for path, data in screens.items():
    print(f"\n{path} ({data['lines']} lines):")
    print(f"  Widgets: {', '.join(data['widgets']) if data['widgets'] else 'None'}")
    print(f"  API Calls: {', '.join(data['api_methods_used']) if data['api_methods_used'] else 'None'}")
