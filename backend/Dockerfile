FROM python:3.12-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY app ./app
COPY config ./config

# Run as an unprivileged user; audio + SQLite live on a mounted volume.
RUN useradd --create-home --uid 10001 appuser \
    && mkdir -p /srv/data/audio \
    && chown -R appuser:appuser /srv/data
USER appuser

ENV LOCAL_STORAGE_DIR=/srv/data/audio \
    SQLITE_PATH=/srv/data/telugu_voice.db \
    VOICES_CONFIG_FILE=/srv/config/voices.yaml \
    PORT=8000

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
    CMD python -c "import urllib.request,os;urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\",\"8000\")}/api/health')" || exit 1

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT} --proxy-headers --forwarded-allow-ips='*'"]
