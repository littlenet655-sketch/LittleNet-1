from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def _text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_native_flutter_android_source_is_canonical_and_webview_free():
    pubspec = _text("mobile_flutter/pubspec.yaml")
    prepare = _text("mobile_flutter/tool/prepare_android.sh")
    main = _text("mobile_flutter/lib/main.dart")
    auth = _text("mobile_flutter/lib/screens/auth.dart")

    assert "LittleNetApp" in main
    assert "image_picker" in pubspec
    assert "flutter_secure_storage" in pubspec
    assert "webview_flutter" not in pubspec.lower()
    assert "android.permission.CAMERA" in prepare
    assert 'android:usesCleartextTraffic="false"' in prepare
    assert "FlutterActivity" in prepare
    assert "com.littlenet.app" in prepare
    assert "ImageSource.camera" in auth
    assert "android.webkit.WebView" not in prepare
    assert not (ROOT / "android/app/src/main/java/com/littlenet/app/MainActivity.java").exists()


def test_native_flutter_ci_builds_release_apk_against_https_mobile_api():
    workflow = _text(".github/workflows/flutter-native.yml")
    assert "flutter build apk --release" in workflow
    assert "LITTLENET_API_BASE=https://" in workflow
    assert "lib/arm64-v8a/libflutter.so" in workflow
    assert "LittleNet-native-Flutter-APK" in workflow
    assert "webview_flutter" in workflow
    assert "WebView dependency/code found in native app" in workflow


def test_signed_android_release_is_flutter_and_keeps_littlenet_package():
    workflow = _text(".github/workflows/release-android.yml")
    assert "flutter build apk --release" in workflow
    assert "LittleNet-signed-native-Flutter-APK" in workflow
    assert "package: name='com.littlenet.app'" in workflow
    assert "lib/arm64-v8a/libflutter.so" in workflow
    assert "adb install -r" in workflow
    assert "com.littlenet.app/.MainActivity" in workflow


def test_live_release_builds_native_flutter_not_legacy_android_wrapper():
    workflow = _text(".github/workflows/deploy-modal.yml")
    assert "Generate exact-branded native Android runner" in workflow
    assert "flutter build apk --release" in workflow
    assert "LITTLENET_API_BASE" in workflow
    assert "LittleNet-live-native-Flutter-APK" in workflow
    assert ":app:assembleDebug" not in workflow
    assert "LittleNet-live-verified-apk" not in workflow


def test_native_mobile_api_health_declares_flutter_no_webview():
    api = _text("mobile/api.py")
    assert 'client="flutter"' in api
    assert "webview=False" in api
    assert "/api/mobile/v1/health" in api
    assert "/api/mobile/v1/auth/login" in api
    assert "/api/mobile/v1/auth/face-login" in api
