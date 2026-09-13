# =============================================================================
# ngo-service — imagem multi-stage otimizada.
# Stage 1 compila as dependências; o runtime só recebe os artefatos prontos,
# roda como usuário não-root e não carrega toolchain de build (menor superfície
# de ataque e menos CVEs no scan do Trivy).
# =============================================================================

# Stage 1: Build
FROM python:3.11-slim AS builder

WORKDIR /app

COPY requirements.txt .
# Instala em /app/.local para ser copiado ao runtime como usuário não-root.
RUN pip install --no-cache-dir --prefix=/app/.local -r requirements.txt

# Stage 2: Runtime
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -r -g 10001 app && useradd -r -u 10001 -g app -d /app app \
    && chown -R app:app /app

COPY --from=builder --chown=app:app /app/.local /app/.local
COPY --chown=app:app . .

ENV PATH=/app/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER 10001

# 8081: API HTTP. 9464: /metrics no formato Prometheus.
EXPOSE 8081 9464

CMD ["gunicorn", "--bind", "0.0.0.0:8081", "--workers", "2", \
     "--timeout", "30", "--access-logfile", "-", "--error-logfile", "-", "app:app"]

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8081/health || exit 1
