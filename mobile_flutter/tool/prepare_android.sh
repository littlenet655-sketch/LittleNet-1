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
VALUES="android/app/src/main/res/values"
mkdir -p "$DRAWABLE" "$VALUES"

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

cat > "$DRAWABLE/launch_background.xml" <<'XML'
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="#FFF9F4" />
    <item android:gravity="center" android:width="108dp" android:height="108dp" android:drawable="@drawable/ic_littlenet" />
</layer-list>
XML

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
s=re.sub(r'android:icon="[^"]+"', 'android:icon="@drawable/ic_littlenet"', s)
if 'android:icon=' not in s:
    s=s.replace('<application', '<application\n        android:icon="@drawable/ic_littlenet"', 1)
if 'android:roundIcon=' not in s:
    s=s.replace('android:icon="@drawable/ic_littlenet"', 'android:icon="@drawable/ic_littlenet"\n        android:roundIcon="@drawable/ic_littlenet"', 1)
if 'android:usesCleartextTraffic=' not in s:
    s=s.replace('android:roundIcon="@drawable/ic_littlenet"', 'android:roundIcon="@drawable/ic_littlenet"\n        android:usesCleartextTraffic="false"', 1)
p.write_text(s)
PY

if grep -R -n -E 'android\.webkit\.WebView|WebViewClient|loadUrl\(' android/app/src/main 2>/dev/null; then
  echo 'ERROR: WebView code found in native Flutter Android runner.' >&2
  exit 1
fi

echo "Prepared native LittleNet Android runner with branded icon/splash and no WebView."
