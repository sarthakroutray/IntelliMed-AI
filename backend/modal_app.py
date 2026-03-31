import os
from pathlib import Path

import modal


APP_NAME = os.getenv("MODAL_APP_NAME", "intellimed-backend")
SECRET_NAME = os.getenv("MODAL_SECRET_NAME", "intellimed-backend-secrets")
APP_LABEL = os.getenv("MODAL_APP_LABEL", "intellimed-backend")

app = modal.App(APP_NAME)

image = modal.Image.from_dockerfile(
    Path(__file__).with_name("Dockerfile"),
    context_dir=Path(__file__).resolve().parent.parent,
)


@app.function(
    image=image,
    cpu=4.0,
    memory=8192,
    scaledown_window=300,
    timeout=1800,
    secrets=[modal.Secret.from_name(SECRET_NAME)],
)
@modal.asgi_app(label=APP_LABEL)
def fastapi_app():
    from main import app as web_app

    return web_app
