"""Vendor pinned MediaPipe Face Landmarker browser assets into LittleNet static files.

The web UI imports these files from ``/static/vendor/mediapipe`` so production
CSP stays ``script-src 'self'`` and Parent camera frames never need to be sent to
an external JavaScript host. Downloads happen only while building/deploying the
web image, not on each request.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import shutil
import sys
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "static" / "vendor" / "mediapipe"
VERSION = "1.0.1"
NPM = f"https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@{VERSION}"
MODEL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"

ASSETS = {
    "vision_bundle.mjs": (f"{NPM}/vision_bundle.mjs", 100_000),
    "wasm/vision_wasm_internal.js": (f"{NPM}/wasm/vision_wasm_internal.js", 100_000),
    "wasm/vision_wasm_internal.wasm": (f"{NPM}/wasm/vision_wasm_internal.wasm", 8_000_000),
    "wasm/vision_wasm_module_internal.js": (f"{NPM}/wasm/vision_wasm_module_internal.js", 100_000),
    "wasm/vision_wasm_module_internal.wasm": (f"{NPM}/wasm/vision_wasm_module_internal.wasm", 8_000_000),
    "wasm/vision_wasm_nosimd_internal.js": (f"{NPM}/wasm/vision_wasm_nosimd_internal.js", 100_000),
    "wasm/vision_wasm_nosimd_internal.wasm": (f"{NPM}/wasm/vision_wasm_nosimd_internal.wasm", 8_000_000),
    "face_landmarker.task": (MODEL, 1_000_000),
}


def _download(url: str, target: Path, minimum_bytes: int) -> str:
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_suffix(target.suffix + ".part")
    request = urllib.request.Request(url, headers={"User-Agent": "LittleNet-build/1"})
    with urllib.request.urlopen(request, timeout=120) as response, temp.open("wb") as output:  # nosec B310 - URLs are fixed HTTPS constants above
        if response.geturl().split(":", 1)[0].lower() != "https":
            raise RuntimeError(f"Refusing non-HTTPS MediaPipe redirect: {response.geturl()}")
        shutil.copyfileobj(response, output)
    size = temp.stat().st_size
    if size < minimum_bytes:
        temp.unlink(missing_ok=True)
        raise RuntimeError(f"MediaPipe asset too small: {target.name} ({size} bytes)")
    digest = hashlib.sha256(temp.read_bytes()).hexdigest()
    temp.replace(target)
    return digest


def main() -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    lines = [f"mediapipe_tasks_vision={VERSION}"]
    for relative, (url, minimum) in ASSETS.items():
        target = DEST / relative
        digest = _download(url, target, minimum)
        lines.append(f"{relative} sha256={digest} bytes={target.stat().st_size}")
        print(lines[-1])
    (DEST / "BUILD-MANIFEST.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
