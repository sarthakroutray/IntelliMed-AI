FROM python:3.11-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    git \
    libgl1 \
    libglib2.0-0 \
    tesseract-ocr \
    openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY backend/requirements.txt /app/backend/requirements.txt

RUN pip install --upgrade pip && \
    pip install -r /app/backend/requirements.txt && \
    pip install modal && \
    python -m spacy download en_core_web_sm

COPY backend /app/backend

RUN mkdir -p /app/backend/uploads && \
    prisma generate --schema=/app/backend/prisma/schema.prisma

WORKDIR /app/backend

EXPOSE 8000

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
