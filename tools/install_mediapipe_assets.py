"""Vendor pinned, integrity-verified MediaPipe Face Landmarker browser assets.

The web UI imports these files from ``/static/vendor/mediapipe`` so production
CSP stays ``script-src 'self'`` and Parent camera frames never need to leave the
device. Assets are fetched only at image-build time.
"""
from __future__ import annotations

import hashlib
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "static" / "vendor" / "mediapipe"
VERSION = "1.0.1"
PACKAGE_URL = "https://registry.npmjs.org/@mediapipe/tasks-vision/-/tasks-vision-1.0.1.tgz"
PACKAGE_SHA256 = "ee318eaa3d42230aa10910d114faf2a488c577c4e4d33c7cb04126924aca505f"
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
MODEL_SHA256 = "64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff"


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _download_verified(url: str, expected_sha256: str, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    temp = target.with_suffix(target.suffix + ".part")
    temp.unlink(missing_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": "LittleNet-build/2"})
    with urllib.request.urlopen(request, timeout=120) as response, temp.open("wb") as output:  # nosec B310 - fixed HTTPS constants
        if response.geturl().split(":", 1)[0].lower() != "https":
            raise RuntimeError(f"Refusing non-HTTPS redirect: {response.geturl()}")
        shutil.copyfileobj(response, output)
    actual = _sha256(temp)
    if actual != expected_sha256:
        temp.unlink(missing_ok=True)
        raise RuntimeError(f"SHA-256 mismatch for {target.name}: {actual}")
    temp.replace(target)


def _extract_runtime(package_path: Path) -> None:
    wanted_prefix = PurePosixPath("package/wasm")
    bundle_name = PurePosixPath("package/vision_bundle.mjs")
    extracted = 0
    with tarfile.open(package_path, "r:gz") as archive:
        for member in archive.getmembers():
            name = PurePosixPath(member.name)
            wanted = name == bundle_name or (len(name.parts) > 2 and PurePosixPath(*name.parts[:2]) == wanted_prefix)
            if not wanted or not member.isfile():
                continue
            if ".." in name.parts:
                raise RuntimeError(f"Unsafe MediaPipe archive member: {member.name}")
            source = archive.extractfile(member)
            if source is None:
                raise RuntimeError(f"Could not read MediaPipe archive member: {member.name}")
            relative = Path(*name.parts[1:])
            target = DEST / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with source, target.open("wb") as output:
                shutil.copyfileobj(source, output)
            extracted += 1
    if extracted < 3 or not (DEST / "vision_bundle.mjs").exists() or not any((DEST / "wasm").glob("*.wasm")):
        raise RuntimeError("Verified MediaPipe package did not contain the expected browser runtime")


def main() -> int:
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="littlenet_mediapipe_") as temp_dir:
        package = Path(temp_dir) / f"tasks-vision-{VERSION}.tgz"
        model = Path(temp_dir) / "face_landmarker.task"
        _download_verified(PACKAGE_URL, PACKAGE_SHA256, package)
        _download_verified(MODEL_URL, MODEL_SHA256, model)

        wasm = DEST / "wasm"
        if wasm.exists():
            shutil.rmtree(wasm)
        (DEST / "vision_bundle.mjs").unlink(missing_ok=True)
        _extract_runtime(package)
        shutil.copy2(model, DEST / "face_landmarker.task")

    manifest_lines = [
        f"mediapipe_tasks_vision={VERSION}",
        f"package_sha256={PACKAGE_SHA256}",
        f"face_landmarker_sha256={MODEL_SHA256}",
    ]
    for path in sorted(p for p in DEST.rglob("*") if p.is_file() and p.name != "BUILD-MANIFEST.txt"):
        manifest_lines.append(f"{path.relative_to(DEST).as_posix()} sha256={_sha256(path)} bytes={path.stat().st_size}")
    (DEST / "BUILD-MANIFEST.txt").write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")
    print("Prepared integrity-verified MediaPipe liveness assets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
