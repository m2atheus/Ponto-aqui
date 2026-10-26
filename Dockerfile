FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies are installed only when this image is built locally.
COPY requirements.txt ./
RUN python -m pip install --no-cache-dir --prefer-binary \
    -r requirements.txt "gunicorn==23.0.0"

RUN groupadd --gid 10001 ponto \
    && useradd --uid 10001 --gid ponto --no-create-home ponto \
    && mkdir -p /app/instance \
    && chown ponto:ponto /app/instance

COPY --chown=ponto:ponto app ./app
COPY --chown=ponto:ponto migrations ./migrations

USER ponto
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/web/', timeout=3)" || exit 1

# One worker avoids multiplying application memory on the 1 GiB VM.
# Do not preload: database connections must belong to the worker process.
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--worker-class", "gthread", "--threads", "2", "--timeout", "60", "--graceful-timeout", "30", "--max-requests", "1000", "--max-requests-jitter", "100", "--access-logfile", "-", "--error-logfile", "-", "app:create_app()"]
