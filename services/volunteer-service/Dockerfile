# =============================================================================
# volunteer-service — imagem multi-stage otimizada (mesma estratégia do
# ngo-service: build separado do runtime, usuário não-root, sem toolchain).
# =============================================================================

# Stage 1: Build
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/app/.local -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get upgrade -y \
    apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r -g 10001 app && useradd -r -u 10001 -g app -d /app app \
    && chown -R app:app /app

COPY --from=builder --chown=app:app /app/.local /app/.local
COPY --chown=app:app . .

ENV PATH=/app/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER 10001

# 8083: API HTTP. 9464: /metrics no formato Prometheus.
EXPOSE 8083 9464

CMD ["gunicorn", "--bind", "0.0.0.0:8083", "--workers", "2", \
     "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8083/health || exit 1
