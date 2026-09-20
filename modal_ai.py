"""Modal deployment for LittleNet's heavy AI inference service.

Deploy from the project root with:
    modal deploy modal_ai.py

Locked scope: text/image/video moderation plus guardian/child face verification.
Standalone audio, voice and story-music moderation are intentionally excluded.
"""
from pathlib import Path
import hashlib
import json
import os
import tempfile

import modal

ROOT = Path(__file__).resolve().parent

app = modal.App("littlenet-ai")
model_cache = modal.Volume.from_name("littlenet-model-cache", create_if_missing=True)
ai_secret = modal.Secret.from_name("littlenet-ai-secrets", required_keys=["AI_SHARED_SECRET"])
web_secret = modal.Secret.from_name("littlenet-web-secrets")
r2_secret = modal.Secret.from_name("littlenet-r2")

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("ffmpeg", "libgl1", "libglib2.0-0", "libgomp1")
    .pip_install(
        "numpy==1.26.4",
        "torch>=2.2,<2.8",
        "torchvision>=0.17,<0.23",
        "transformers>=4.45,<5",
        "detoxify==0.5.2",
        "nudenet>=3.4,<4",
        "deepface>=0.0.93,<0.1",
        "tensorflow>=2.16,<2.19",
        "tf-keras>=2.16,<2.19",
        "ultralytics>=8.3,<9",
        "opencv-python-headless==4.11.0.86",
        "scenedetect-headless>=0.7,<0.8",
        "Flask==3.1.3",
        "python-dotenv==1.2.2",
        "Pillow==12.3.0",
        "pypdf==6.16.1",
        "requests==2.33.0",
        "psycopg2-binary==2.9.10",
        "boto3==1.40.17",
    )
    .workdir("/root/littlenet")
    .env(
        {
            "LITTLENET_AI_SERVER": "1",
            "LITTLENET_DEVICE": "cuda",
            "LITTLENET_MODEL_CACHE": "/cache/models",
            "HF_HOME": "/cache/huggingface",
            "HF_HUB_CACHE": "/cache/huggingface/hub",
            "TORCH_HOME": "/cache/torch",
            "DEEPFACE_HOME": "/cache/deepface",
            "LITTLENET_DETOXIFY_MODEL": "multilingual",
            # Scene-aware sampling protects short scene changes. The bounded
            # uniform fallback prevents long reels from multiplying GPU work.
            # Cost-bounded video scan: short clips retain <=4s temporal spacing.
            # Long clips stop at 24 frames and fail to REVIEW rather than burning
            # unbounded GPU time to auto-allow them.
            "LITTLENET_VIDEO_SAMPLE_INTERVAL_SECONDS": "4",
            "LITTLENET_VIDEO_MAX_FRAMES": "24",
            # Longer videos remain private for review if this temporal coverage
            # cannot be met within the full-model frame budget.
            "LITTLENET_VIDEO_MAX_AUTO_ALLOW_GAP_SECONDS": "4",
            "LITTLENET_ENABLE_SCENEDETECT": "1",
            "LITTLENET_SCENEDETECT_THRESHOLD": "27",
            "LITTLENET_YOLO_WEIGHTS": "/root/littlenet/yolov8n-oiv7.pt",
            "LITTLENET_YOLO_REVIEW_THRESHOLD": "0.20",
            "LITTLENET_YOLO_BLOCK_THRESHOLD": "0.45",
            "LITTLENET_NUDENET_REVIEW_THRESHOLD": "0.20",
            "LITTLENET_NUDENET_BLOCK_THRESHOLD": "0.45",
            "LITTLENET_FALCONSAI_REVIEW_THRESHOLD": "0.40",
            "LITTLENET_FALCONSAI_BLOCK_THRESHOLD": "0.70",
            "LITTLENET_CLIP_REVIEW_THRESHOLD": "0.40",
            "LITTLENET_CLIP_BLOCK_THRESHOLD": "0.65",
            "LITTLENET_DEPLOY_VERSION": "13",
        }
    )
    .add_local_dir(
        str(ROOT),
        remote_path="/root/littlenet",
        ignore=[
            ".git/**", ".pytest_cache/**", "**/__pycache__/**", "uploads/**",
            "android/**", "android-build/**", "mobile_app/**", "mobile_flutter/**", "datasets/**",
            "test-results/**", "playwright-report/**", "tools/gradle-8.9/**",
            "node_modules/**", ".agent/**", ".agents/**", "agent/**",
            ".claude/**", ".cursor/**", "*.db", "*.zip", "*.apk", ".env",
        ],
        copy=True,
    )
)
secret_preflight_image = modal.Image.debian_slim(python_version="3.11")


def _secret_fingerprint(value: str | None) -> dict[str, object]:
    """Return non-disclosing presence and equality data for a shared secret."""
    normalized = str(value or "")
    if not normalized:
        return {"present": False, "fingerprint": None}
    return {
        "present": True,
        "fingerprint": hashlib.sha256(normalized.encode("utf-8")).hexdigest(),
    }


@app.function(
    image=image,
    gpu="T4",
    cpu=4.0,
    memory=8192,
    secrets=[ai_secret, web_secret, r2_secret],
    volumes={"/cache": model_cache},
    timeout=900,
    startup_timeout=900,
    # Scale fully to zero. Keep only a short warm tail so a small demo burst is
    # responsive without paying for minutes of idle GPU after every request.
    scaledown_window=int(os.getenv("MODAL_AI_GPU_SCALEDOWN_WINDOW", "30")),
    min_containers=0,
    max_containers=1,
)
@modal.concurrent(max_inputs=1, target_inputs=1)
@modal.wsgi_app()
def ai_web():
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    os.environ["TF_ENABLE_ONEDNN_OPTS"] = "0"
    try:
        import tensorflow as tf
        tf.config.set_visible_devices([], 'GPU')
    except Exception:
        pass
    from ai_server import app as flask_ai_app
    return flask_ai_app


@app.function(
    image=image,
    cpu=4.0,
    memory=8192,
    volumes={"/cache": model_cache},
    timeout=600,
    startup_timeout=900,
    # Images are processed asynchronously. Keep a short CPU warm tail for a
    # burst of posts, then return fully to zero.
    scaledown_window=int(os.getenv("MODAL_AI_IMAGE_CPU_SCALEDOWN_WINDOW", "30")),
    min_containers=0,
    max_containers=1,
)
@modal.concurrent(max_inputs=1, target_inputs=1)
def moderate_image_upload_cpu(
    file_bytes: bytes,
    filename: str = "upload.jpg",
    text: str = "",
    run_text: bool = True,
    run_media: bool = True,
):
    """Run upload image moderation on CPU so ordinary photos never require T4 credit."""
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
    os.environ["LITTLENET_AI_SERVER"] = "1"
    os.environ["LITTLENET_DEVICE"] = "cpu"

    path = None
    if run_media:
        suffix = Path(filename or "upload.jpg").suffix.lower()
        if suffix not in {".jpg", ".jpeg", ".png", ".webp"}:
            suffix = ".jpg"
        fd, path = tempfile.mkstemp(prefix="littlenet_cpu_image_", suffix=suffix)
        os.close(fd)

    def jsonable(value):
        if isinstance(value, dict):
            return {str(k): jsonable(v) for k, v in value.items()}
        if isinstance(value, (list, tuple)):
            return [jsonable(v) for v in value]
        if hasattr(value, "item"):
            try:
                return value.item()
            except Exception:
                return str(value)
        return value

    try:
        if run_media:
            with open(path, "wb") as fh:
                fh.write(file_bytes or b"")
            if os.path.getsize(path) <= 0:
                raise ValueError("image_payload_empty")

        text_signals = {}
        media_signals = {}
        if run_text and text:
            from safety.text_service import check_text
            text_signals = check_text(text[:4000])
        if run_media:
            from safety.visual_service import check_image
            media_signals = check_image(path)

        # Persist model downloads only when this workload's cache was first
        # populated. Avoid a Volume commit on every moderation request.
        cache_markers = []
        if run_text:
            cache_markers.append(Path("/cache/.cpu_text_models_ready"))
        if run_media:
            cache_markers.append(Path("/cache/.cpu_image_models_ready"))
        missing_markers = [marker for marker in cache_markers if not marker.exists()]
        if missing_markers:
            try:
                for marker in missing_markers:
                    marker.write_text("ready", encoding="utf-8")
                model_cache.commit()
            except Exception:
                for marker in missing_markers:
                    try:
                        marker.unlink(missing_ok=True)
                    except Exception:
                        pass

        return {
            "ok": True,
            "text_signals": jsonable(text_signals),
            "media_signals": jsonable(media_signals),
            "compute_tier": "cpu",
        }
    finally:
        if path:
            try:
                os.unlink(path)
            except OSError:
                pass


@app.function(
    image=secret_preflight_image,
    secrets=[ai_secret],
    timeout=60,
    min_containers=0,
    max_containers=1,
)
def ai_secret_preflight():
    """Read only the AI secret for a non-disclosing release comparison."""
    return _secret_fingerprint(os.environ.get("AI_SHARED_SECRET"))


@app.function(
    image=image,
    cpu=2.0,
    memory=4096,
    secrets=[ai_secret],
    volumes={"/cache": model_cache},
    timeout=900,
    min_containers=0,
    max_containers=1,
)
def prepare_face_cache():
    """Prepare FaceNet512 on CPU so model caching does not consume GPU credit."""
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    os.environ["CUDA_VISIBLE_DEVICES"] = "-1"
    os.environ["LITTLENET_DEVICE"] = "cpu"
    import importlib

    # DeepFace's public `from deepface import DeepFace` import can resolve the
    # DeepFace submodule even when it is not a direct package attribute. Import
    # the submodule explicitly so this helper works across supported versions.
    deepface_module = importlib.import_module("deepface.DeepFace")
    model = deepface_module.build_model("Facenet512")
    if model is None:
        raise RuntimeError("Facenet512 model did not initialize")
    model_cache.commit()
    return {"ok": True, "model": "Facenet512", "device": "cpu", "cached": True}


@app.function(
    image=image,
    gpu="T4",
    cpu=4.0,
    memory=8192,
    secrets=[ai_secret],
    volumes={"/cache": model_cache},
    timeout=1800,
    min_containers=0,
    max_containers=1,
)
def warm_models():
    """Explicit full GPU validation gate. Do not use for routine deployment."""
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    os.environ["LITTLENET_AI_SERVER"] = "1"
    os.environ["LITTLENET_DEVICE"] = "cuda"
    os.environ["LITTLENET_DETOXIFY_MODEL"] = "multilingual"

    results = {}

    def run(name, fn):
        try:
            detail = fn()
            results[name] = {"ok": True}
            if detail is not None:
                results[name]["detail"] = detail
        except Exception as exc:
            results[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}

    import importlib

    def detoxify_explicit():
        Detoxify = importlib.import_module("detoxify").Detoxify
        model = Detoxify("multilingual")
        scores = model.predict("Hello, this is a normal LittleNet safety warmup sentence.")
        if "sexual_explicit" not in scores:
            raise RuntimeError("Detoxify multilingual model is missing sexual_explicit output")
        return {"labels": sorted(scores.keys())}
    run("detoxify_multilingual_explicit", detoxify_explicit)

    def nudenet_validate():
        NudeDetector = importlib.import_module("nudenet").NudeDetector
        detector = NudeDetector()
        return {"loaded": detector is not None}
    run("nudenet", nudenet_validate)

    def clip():
        transformers = importlib.import_module("transformers")
        CLIPModel = transformers.CLIPModel
        CLIPProcessor = transformers.CLIPProcessor
        CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
        CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
    run("clip", clip)

    def falconsai():
        pipeline = importlib.import_module("transformers").pipeline
        pipeline("image-classification", model="Falconsai/nsfw_image_detection", device=0)
    run("falconsai_nsfw", falconsai)

    def yolo():
        YOLO = importlib.import_module("ultralytics").YOLO
        from safety.yolo_policy import dangerous_label_coverage
        model = YOLO("/root/littlenet/yolov8n-oiv7.pt")
        matched = dangerous_label_coverage(model.names)
        if len(matched) < 3:
            raise RuntimeError(f"YOLO checkpoint exposes insufficient dangerous-object labels: {matched}")
        return {"dangerous_labels": list(matched)}
    run("yolo_oiv7", yolo)

    def face():
        deepface_module = importlib.import_module("deepface.DeepFace")
        model = deepface_module.build_model("Facenet512")
        if model is None:
            raise RuntimeError("Facenet512 model did not initialize")
        return {"loaded": True}
    run("deepface_facenet512", face)

    def scene_detect():
        scenedetect = importlib.import_module("scenedetect")
        detectors = importlib.import_module("scenedetect.detectors")
        SceneManager = scenedetect.SceneManager
        open_video = scenedetect.open_video
        ContentDetector = detectors.ContentDetector
        _ = SceneManager(); _ = ContentDetector(threshold=27)
        return {"available": callable(open_video)}
    run("pyscenedetect", scene_detect)

    # Persist successful downloads even when a later validation fails. This
    # prevents a retry from downloading gigabytes again.
    model_cache.commit()
    failed = {name: value for name, value in results.items() if not value.get("ok")}
    if failed:
        raise RuntimeError(f"LittleNet AI warmup failed: {failed}")
    return results


@app.local_entrypoint()
def main(
    confirm_gpu_warmup: bool = False,
    prepare_face_cache_only: bool = False,
    secret_preflight: bool = False,
):
    """Cost-guarded maintenance entrypoint."""
    if secret_preflight:
        report = ai_secret_preflight.remote()
        print(f"secret-preflight {json.dumps(report, sort_keys=True)}")
        return
    if prepare_face_cache_only:
        report = prepare_face_cache.remote()
        print(f"OK   face-cache: {report}")
        return
    if not confirm_gpu_warmup:
        print("GPU warmup skipped. This command is intentionally cost-guarded.")
        print("Cheap face-cache preparation: modal run modal_ai.py --prepare-face-cache-only")
        print("Full GPU validation only when intentional: modal run modal_ai.py --confirm-gpu-warmup")
        return
    report = warm_models.remote()
    for name, result in report.items():
        print(f"{'OK' if result['ok'] else 'FAIL':4} {name}: {result.get('error', '')}")
