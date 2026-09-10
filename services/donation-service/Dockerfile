# =============================================================================
# donation-service (Hot Path) — multi-stage build.
# O binário é estático (CGO_ENABLED=0) e o runtime é um alpine mínimo sem
# toolchain Go, o que reduz drasticamente as CVEs reportadas pelo Trivy.
# =============================================================================

# Stage 1: Build
FROM golang:1.24-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git

# Cache de dependências
COPY go.mod ./
RUN go mod download || true
COPY . .
RUN go mod tidy

# Build estático, sem símbolos de debug (-s -w) e sem paths absolutos (-trimpath)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -trimpath -ldflags="-s -w" -o donation-service .

# Stage 2: Runtime
FROM alpine:3.20

RUN apk add --no-cache ca-certificates \
 && addgroup -S app && adduser -S -G app app

WORKDIR /app
COPY --from=builder /app/donation-service .
RUN chown -R app:app /app
USER app

# 8082: API HTTP. 9464: /metrics no formato Prometheus.
EXPOSE 8082 9464

CMD ["./donation-service"]

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8082/health || exit 1
