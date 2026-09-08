#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -d android ]; then
  flutter create . --platforms=android --org com.littlenet --project-name littlenet_native
fi

# flutter create adds its stock MyApp widget test; LittleNet has its own tests.
rm -f test/widget_test.dart

MANIFEST="android/app/src/main/AndroidManifest.xml"
DRAWABLE="android/app/src/main/res/drawable"
DRAWABLE_V21="android/app/src/main/res/drawable-v21"
VALUES="android/app/src/main/res/values"
BUILD_GRADLE="android/app/build.gradle.kts"
mkdir -p "$DRAWABLE" "$DRAWABLE_V21" "$VALUES"

# Preserve LittleNet's existing Android package identity rather than shipping the
# Flutter rewrite as a second unrelated app.
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

# Keep a vector fallback, but use the repository's real LittleNet logo PNG for
# both launcher branding and splash. This makes the native client independent of
# the retired Android WebView project.
cat > "$DRAWABLE/ic_littlenet.xml" <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#0B0F19" android:pathData="M0,0h108v108h-108z"/>
    <path android:fillColor="#8B5CF6" android:pathData="M54,16C71,16 83,23 86,30C86,59 69,80 54,92C39,80 22,59 22,30C25,23 37,16 54,16Z"/>
    <path android:fillColor="#1E1B4B" android:pathData="M54,23C67,23 76,28 78,34C78,57 65,74 54,84C43,74 30,57 30,34C32,28 41,23 54,23Z"/>
    <path android:fillColor="#FFFFFF" android:pathData="M54,34 L58,49 L73,53 L58,57 L54,72 L50,57 L35,53 L50,49 Z"/>
    <path android:fillColor="#EC4899" android:pathData="M54,49a4,4 0,1 0,0.01 0Z"/>
</vector>
XML

BRAND_LOGO="../static/icons/app_logo.png"
test -f "$BRAND_LOGO"
cp "$BRAND_LOGO" "$DRAWABLE/littlenet_brand.png"

cat > "$VALUES/colors.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="littlenet_splash_bg">#FFF9F4</color>
</resources>
XML

write_launch_background() {
  local target="$1"
  cat > "$target" <<'XML'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/littlenet_splash_bg" />
    <item>
        <bitmap
            android:gravity="center"
            android:src="@drawable/littlenet_brand" />
    </item>
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
launcher = '@drawable/littlenet_brand'
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

# Fail closed if the generated Android app ever regresses to a WebView wrapper.
if grep -R -n -E 'android\.webkit\.WebView|WebViewClient|loadUrl\(' android/app/src/main 2>/dev/null; then
  echo 'ERROR: WebView code found in native Flutter Android runner.' >&2
  exit 1
fi

# Branding/package contract: exact repo logo, branded splash, and the existing
# LittleNet Android application id must all be present.
test -f "$DRAWABLE/littlenet_brand.png"
grep -q 'littlenet_brand' "$DRAWABLE/launch_background.xml"
grep -q 'littlenet_brand' "$DRAWABLE_V21/launch_background.xml"
grep -q 'littlenet_splash_bg' "$VALUES/colors.xml"
grep -q '@drawable/littlenet_brand' "$MANIFEST"
grep -q 'applicationId = "com.littlenet.app"' "$BUILD_GRADLE"
grep -q 'namespace = "com.littlenet.app"' "$BUILD_GRADLE"
grep -q '^package com.littlenet.app$' android/app/src/main/kotlin/com/littlenet/app/MainActivity.kt

echo "Prepared native LittleNet Android runner with exact logo, branded splash, preserved package id and no WebView."
