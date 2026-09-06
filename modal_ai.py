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
        "Flask==3.1.2",
        "python-dotenv==1.1.1",
        "Pillow==11.3.0",
        "pypdf==5.9.0",
        "requests==2.32.5",
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
            "LITTLENET_YOLO_WEIGHTS": "/root/littlenet/yolov8n-oiv7.pt",
            "LITTLENET_YOLO_REVIEW_THRESHOLD": "0.20",
            "LITTLENET_YOLO_BLOCK_THRESHOLD": "0.45",
            "LITTLENET_DEPLOY_VERSION": "6",
        }
    )
    .add_local_dir(
        str(ROOT),
        remote_path="/root/littlenet",
        ignore=[
            ".git/**",
            ".pytest_cache/**",
            "**/__pycache__/**",
            "uploads/**",
            "android/**",
            "tools/gradle-8.9/**",
            "node_modules/**",
            ".agent/**",
            ".agents/**",
            "agent/**",
            ".claude/**",
            ".cursor/**",
            "*.db",
            "*.zip",
            "*.apk",
            ".env",
        ],
        copy=True,
    )
)


@app.function(
    image=image,
    gpu="T4",
    cpu=4.0,
    memory=8192,
    secrets=[ai_secret],
    volumes={"/cache": model_cache},
    timeout=900,
    startup_timeout=900,
    scaledown_window=300,
    min_containers=0,
    max_containers=2,
)
@modal.concurrent(max_inputs=2, target_inputs=1)
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
    """Warm every model in the locked moderation/face stack."""
    os.chdir("/root/littlenet")
    Path("/cache/models").mkdir(parents=True, exist_ok=True)
    os.environ["LITTLENET_AI_SERVER"] = "1"
    os.environ["LITTLENET_DEVICE"] = "cuda"

    results = {}

    def run(name, fn):
        try:
            detail = fn()
            results[name] = {"ok": True}
            if detail is not None:
                results[name]["detail"] = detail
        except Exception as exc:
            results[name] = {"ok": False, "error": f"{type(exc).__name__}: {exc}"}

    run("detoxify", lambda: __import__("detoxify").Detoxify("original"))
    run("nudenet", lambda: __import__("nudenet").NudeDetector())

    def clip():
        from transformers import CLIPModel, CLIPProcessor
        CLIPModel.from_pretrained("openai/clip-vit-base-patch32")
        CLIPProcessor.from_pretrained("openai/clip-vit-base-patch32")
    run("clip", clip)

    def falconsai():
        from transformers import pipeline
        pipeline("image-classification", model="Falconsai/nsfw_image_detection", device=0)
    run("falconsai_nsfw", falconsai)

    def yolo():
        from ultralytics import YOLO
        from safety.yolo_policy import dangerous_label_coverage
        model = YOLO("/root/littlenet/yolov8n-oiv7.pt")
        matched = dangerous_label_coverage(model.names)
        if len(matched) < 3:
            raise RuntimeError(f"YOLO checkpoint exposes insufficient dangerous-object labels: {matched}")
        return {"dangerous_labels": matched}
    run("yolo_oiv7", yolo)

    def face():
        from deepface import DeepFace
        DeepFace.build_model("Facenet512")
    run("deepface_facenet512", face)

    model_cache.commit()
    return results


@app.local_entrypoint()
def main():
    report = warm_models.remote()
    for name, result in report.items():
        print(f"{'OK' if result['ok'] else 'FAIL':4} {name}: {result.get('error', '')}")
