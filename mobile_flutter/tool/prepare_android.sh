#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d android ]; then
  flutter create . --platforms=android --org com.littlenet --project-name littlenet_native
fi

rm -f test/widget_test.dart

MANIFEST="android/app/src/main/AndroidManifest.xml"
DRAWABLE="android/app/src/main/res/drawable"
DRAWABLE_V21="android/app/src/main/res/drawable-v21"
VALUES="android/app/src/main/res/values"
BUILD_GRADLE="android/app/build.gradle.kts"
mkdir -p "$DRAWABLE" "$DRAWABLE_V21" "$VALUES"

python3 - <<'PY'
from pathlib import Path
p = Path('android/app/build.gradle.kts')
s = p.read_text()
s = s.replace('com.littlenet.littlenet_native', 'com.littlenet.app')
p.write_text(s)
PY
rm -rf android/app/src/main/kotlin/com/littlenet/littlenet_native
mkdir -p android/app/src/main/kotlin/com/littlenet/app
cat > android/app/src/main/kotlin/com/littlenet/app/MainActivity.kt <<'KT'
package com.littlenet.app

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
KT

# Launcher/splash mark ported from the uploaded Stitch littlenet_wordmark_logo:
# blue dot + smile curve on a clean white canvas.
cat > "$DRAWABLE/ic_littlenet.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#FFFFFF" android:pathData="M0,0h108v108h-108z" />
    <path android:fillColor="#0095F6" android:pathData="M31,28a8,8 0,1 0,0.01 0z" />
    <path
        android:fillColor="@android:color/transparent"
        android:strokeColor="#0095F6"
        android:strokeWidth="8"
        android:strokeLineCap="round"
        android:pathData="M57,68 C64,53 84,53 91,68" />
</vector>
XML

cat > "$VALUES/colors.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="littlenet_splash_bg">#FFFFFF</color>
</resources>
XML

write_launch_background() {
  local target="$1"
  cat > "$target" <<'XML'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/littlenet_splash_bg" />
    <item android:drawable="@drawable/ic_littlenet" />
</layer-list>
XML
}
write_launch_background "$DRAWABLE/launch_background.xml"
write_launch_background "$DRAWABLE_V21/launch_background.xml"

python3 - <<'PY'
from pathlib import Path
import re
p=Path('android/app/src/main/AndroidManifest.xml')
s=p.read_text()
permissions = [
    '<uses-permission android:name="android.permission.CAMERA" />',
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES" />',
    '<uses-permission android:name="android.permission.READ_MEDIA_VIDEO" />',
]
for permission in permissions:
    if permission not in s:
        s=s.replace('<application', permission+'\n    <application', 1)
s=s.replace('android:label="littlenet_native"', 'android:label="LittleNet"')
s=s.replace('android:label="littlenet native"', 'android:label="LittleNet"')
launcher = '@drawable/ic_littlenet'
s=re.sub(r'android:icon="[^"]+"', f'android:icon="{launcher}"', s)
if 'android:icon=' not in s:
    s=s.replace('<application', f'<application\n        android:icon="{launcher}"', 1)
if 'android:roundIcon=' not in s:
    s=s.replace(f'android:icon="{launcher}"', f'android:icon="{launcher}"\n        android:roundIcon="{launcher}"', 1)
else:
    s=re.sub(r'android:roundIcon="[^"]+"', f'android:roundIcon="{launcher}"', s)
if 'android:usesCleartextTraffic=' not in s:
    s=s.replace(f'android:roundIcon="{launcher}"', f'android:roundIcon="{launcher}"\n        android:usesCleartextTraffic="false"', 1)
p.write_text(s)
PY

if grep -R -n -E 'android\.webkit\.WebView|WebViewClient|loadUrl\(' android/app/src/main 2>/dev/null; then
  echo 'ERROR: WebView code found in native Flutter Android runner.' >&2
  exit 1
fi

test -s "$DRAWABLE/ic_littlenet.xml"
grep -q '#0095F6' "$DRAWABLE/ic_littlenet.xml"
grep -q 'ic_littlenet' "$DRAWABLE/launch_background.xml"
grep -q 'littlenet_splash_bg' "$VALUES/colors.xml"
grep -q '@drawable/ic_littlenet' "$MANIFEST"
grep -q 'applicationId = "com.littlenet.app"' "$BUILD_GRADLE"
grep -q 'namespace = "com.littlenet.app"' "$BUILD_GRADLE"
grep -q '^package com.littlenet.app$' android/app/src/main/kotlin/com/littlenet/app/MainActivity.kt

echo "Prepared native LittleNet Android runner with Stitch smile-mark branding, preserved package id and no WebView."
