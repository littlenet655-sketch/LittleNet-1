"""Modal deployment for LittleNet's heavy AI inference service.

Deploy from the project root with:
    modal deploy modal_ai.py

Locked scope: text/image/video moderation plus guardian/child face verification.
Standalone audio, voice and story-music moderation are intentionally excluded.
"""
from pathlib import Path
import os

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
        "qstash>=3.4.0,<4",
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
            # Scene-aware sampling already protects short scene changes. A 4 s
            # uniform backup interval plus a 24-frame cap keeps long reels from
            # multiplying GPU work while retaining scene-selected evidence.
            "LITTLENET_VIDEO_SAMPLE_INTERVAL_SECONDS": "4",
            "LITTLENET_VIDEO_MAX_FRAMES": "24",
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
            "LITTLENET_DEPLOY_VERSION": "11",
        }
    )
    .add_local_dir(
        str(ROOT),
        remote_path="/root/littlenet",
        ignore=[
            ".git/**", ".pytest_cache/**", "**/__pycache__/**", "uploads/**",
            "android/**", "android-build/**", "mobile_flutter/**", "datasets/**",
            "test-results/**", "playwright-report/**", "tools/gradle-8.9/**",
            "node_modules/**", ".agent/**", ".agents/**", "agent/**",
            ".claude/**", ".cursor/**", "*.db", "*.zip", "*.apk", ".env",
        ],
        copy=True,
    )
)


@app.function(
    image=image,
    gpu="T4",
    cpu=4.0,
    memory=8192,
    secrets=[ai_secret, web_secret, r2_secret],
    volumes={"/cache": model_cache},
    timeout=900,
    startup_timeout=900,
    # Keep scale-to-zero, but release an idle T4 much sooner than the old
    # five-minute window. 120 s is a compromise between demo responsiveness
    # and credit usage after bursts of uploads.
    scaledown_window=120,
    min_containers=0,
    # One GPU worker is enough for the current college/demo load and prevents
    # short bursts from doubling GPU spend.
    max_containers=1,
)
# These models execute synchronously and compete for GPU/CPU memory. One heavy
# request per container gives more predictable latency than overlapping two.
@modal.concurrent(max_inputs=1, target_inputs=1)
@modal.wsgi_app()
def ai_web():
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    from ai_server import app as flask_ai_app
    return flask_ai_app


@app.function(
    image=image,
    gpu="T4",
    cpu=4.0,
    memory=8192,
    secrets=[ai_secret],
    volumes={"/cache": model_cache},
    timeout=1800,
)
def warm_models():
    """Warm every model/dependency in the locked moderation/face stack.

    A failed component raises after reporting all failures, turning this command
    into a deployment/release gate rather than a diagnostic that can be ignored.
    Only plain serializable metadata is returned to Modal; model/session objects
    stay inside the remote container and are never sent back to the caller.
    """
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
        # NudeDetector owns an ONNX Runtime InferenceSession, which is not
        # pickleable. Validate construction here but return only plain metadata.
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
        DeepFace = importlib.import_module("deepface").DeepFace
        DeepFace.build_model("Facenet512")
    run("deepface_facenet512", face)

    def scene_detect():
        scenedetect = importlib.import_module("scenedetect")
        detectors = importlib.import_module("scenedetect.detectors")
        SceneManager = scenedetect.SceneManager
        open_video = scenedetect.open_video
        ContentDetector = detectors.ContentDetector
        # Constructor/import validation catches incompatible OpenCV/PySceneDetect
        # deployments without requiring a persistent sample video in production.
        _ = SceneManager(); _ = ContentDetector(threshold=27)
        return {"available": callable(open_video)}
    run("pyscenedetect", scene_detect)

    model_cache.commit()
    failed = {name: value for name, value in results.items() if not value.get("ok")}
    if failed:
        raise RuntimeError(f"LittleNet AI warmup failed: {failed}")
    return results


@app.local_entrypoint()
def main():
    report = warm_models.remote()
    for name, result in report.items():
        print(f"{'OK' if result['ok'] else 'FAIL':4} {name}: {result.get('error', '')}")
