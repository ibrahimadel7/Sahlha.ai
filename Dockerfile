# Sahlha.ai backend — Cloudflare Containers ready.
# Heavy deps (torch/sentence-transformers, scikit-learn, tesseract, poppler)
# cannot run on Workers (V8 isolates). Containers run this exact image.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PORT=8000

# System deps: OCR binaries + image/PDF handling.
# tesseract-ocr + Arabic+English packs match OCR_LANGUAGES=eng+ara default.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-ara \
    poppler-utils \
    libgl1 \
    libglib2.0-0 \
    build-essential \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps first for better layer caching.
COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

# App code only (data/, .env, mobile/build excluded via .dockerignore).
COPY sahlha ./sahlha

# Runtime dirs (ephemeral on Cloudflare Containers — see wrangler notes).
RUN mkdir -p /app/data/uploads /app/data/audio /app/data/images

EXPOSE 8000

# Single worker: SQLite + in-process vector cache are single-writer by design.
CMD ["sh", "-c", "python -m uvicorn sahlha.app.main:app --host 0.0.0.0 --port ${PORT:-8000} --workers 1"]
