"""Operator-only Modal helper for LittleNet college demo accounts.

This file deliberately contains no demo password. The password must be stored
privately as LITTLENET_DEMO_PASSWORD inside the existing
`littlenet-web-secrets` Modal secret. The helper is never called by the web
application and therefore creates no public setup endpoint.
"""
import os
import subprocess

import modal

from modal_web import web_image, web_secret

app = modal.App("littlenet-demo-tools")


@app.function(image=web_image, secrets=[web_secret], timeout=180)
def seed_demo_accounts():
    password = os.getenv("LITTLENET_DEMO_PASSWORD", "")
    if len(password) < 12:
        raise RuntimeError(
            "Add LITTLENET_DEMO_PASSWORD (12+ characters) to the private "
            "Modal secret littlenet-web-secrets before seeding demo accounts."
        )

    env = os.environ.copy()
    env["LITTLENET_ENABLE_DEMO_SEED"] = "1"
    subprocess.run(
        ["python", "tools/seed_demo_accounts.py"],
        cwd="/root/littlenet",
        env=env,
        check=True,
    )
    return {
        "ok": True,
        "accounts": {
            "kid": "ait_star_student",
            "parent": "mentor_parent@ait.edu",
            "admin": "admin@littlenet.com",
        },
    }


@app.local_entrypoint()
def main():
    result = seed_demo_accounts.remote()
    print("LittleNet demo accounts seeded:", result)
