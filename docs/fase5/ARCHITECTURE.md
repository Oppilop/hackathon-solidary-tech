# Arquitetura — SolidaryTech (Hackathon Fase 5)

> Plataforma que conecta ONGs, doadores e voluntários. Três microsserviços em
> Kubernetes (EKS), provisionados 100% por Terraform, entregues por GitOps,
> observados de ponta a ponta e protegidos por um plano de continuidade.

---

## 1. Visão macro

```
                              Internet
                                 │
                          ┌──────▼──────┐
                          │  NLB (AWS)  │
                          └──────┬──────┘
                                 │
                        ┌────────▼────────┐
                        │  ingress-nginx  │  /api/<serviço>/*
                        └───┬────┬────┬───┘
             ┌──────────────┘    │    └──────────────┐
             │                   │                   │
     ┌───────▼───────┐   ┌───────▼────────┐  ┌───────▼──────────┐
     │  ngo-service  │   │ donation-svc   │  │ volunteer-svc    │
     │  Python/Flask │   │ Go (HOT PATH)  │  │ Python/Flask     │
     │  :8081        │   │ :8082          │  │ :8083            │
     └───────┬───────┘   └───┬────────┬───┘  └───────┬──────────┘
             │               │        │              │
     ┌───────▼──────┐ ┌──────▼─────┐ ┌▼──────────┐ ┌─▼──────────────┐
     │ RDS ngodb    │ │RDS donation│ │ SQS       │ │ DynamoDB       │
     │ PostgreSQL   │ │PostgreSQL  │ │ donations │ │ Volunteers     │
     └──────────────┘ └────────────┘ └───────────┘ └────────────────┘

  Telemetria (OTLP) de todos os serviços
             │
     ┌───────▼───────────────────┐
     │ OTel Collector (DaemonSet)│──┬─► Datadog APM (traces + Watchdog/AIOps)
     └───────────────────────────┘  ├─► Prometheus (métricas)
                                    └─► Loki (logs)
                                            │
                                        Grafana ── painel SRE (SLO/Error Budget)
                                            │
                                       Alertmanager
                                            │
                                   PagerDuty ──┬─► Discord (#incidentes)
                                               └─► self-healing-webhook
                                                        │
                                                kubectl rollout restart
```

---

## 2. Microsserviços

| Serviço | Linguagem | Porta | Persistência | Papel |
|---|---|---|---|---|
| `ngo-service` | Python 3.11 / Flask | 8081 | RDS PostgreSQL (`ngodb`) | Cadastro e consulta de ONGs parceiras |
| `donation-service` | Go 1.24 | 8082 | RDS PostgreSQL (`donationdb`) + SQS | **Hot Path**: processa doações e publica eventos |
| `volunteer-service` | Python 3.11 / Flask | 8083 | DynamoDB (`SolidaryTechVolunteers`) | Match entre voluntários e campanhas |

O `donation-service` é o **componente crítico**: é o único com SLO formal,
error budget monitorado, 2 réplicas mínimas, PodDisruptionBudget,
anti-afinidade entre nodes e backup horário.

### Rotas expostas

| Rota pública | Backend |
|---|---|
| `GET/POST /api/ngo/ngos` | ngo-service |
| `GET /api/ngo/health` | ngo-service |
| `GET/POST /api/donation/donations` | donation-service |
| `GET /api/donation/health` | donation-service |
| `GET/POST /api/volunteer/volunteers` | volunteer-service |
| `GET /api/volunteer/health` | volunteer-service |

O prefixo `/api/<serviço>` seleciona o backend e é removido pelo rewrite do
ingress, preservando o path original da aplicação.

---

## 3. Fundação DevOps (Fases 1 a 4 aplicadas ao novo ecossistema)

### 3.1 Docker

Todas as imagens usam **multi-stage build**: o estágio de build carrega o
compilador/pip e o estágio final recebe apenas o artefato. Resultado: menos
CVEs no scan e imagem menor.

- Go: binário estático (`CGO_ENABLED=0`, `-trimpath -ldflags="-s -w"`) sobre
  `alpine:3.20`.
- Python: dependências instaladas em `--prefix=/app/.local` e copiadas para
  um `python:3.11-slim` sem toolchain.
- Todos rodam como usuário **não-root**, com `HEALTHCHECK` próprio.

### 3.2 Kubernetes

- Um namespace por serviço (`ngo-namespace`, `donation-namespace`,
  `volunteer-namespace`), isolando Secrets e ConfigMaps.
- `requests`/`limits` declarados em **todos** os containers (rightsizing —
  ver [FINOPS.md](FINOPS.md)).
- Probes `readiness` e `liveness` em `/health`.
- HPA por CPU em todos os serviços; o Hot Path escala a partir de 65% e tem
  `behavior` assimétrico (sobe rápido, desce devagar).
- `securityContext` restritivo: `allowPrivilegeEscalation: false`,
  `runAsNonRoot`, `capabilities.drop: [ALL]`.

### 3.3 Infraestrutura como Código (Terraform)

```
terraform/
├── main.tf              # composição do ambiente primário
├── variables.tf         # inclui a política de tags de FinOps
├── providers.tf         # default_tags + provider alias da região de DR
├── modules/
│   ├── networking/      # VPC, subnets pública/privada, IGW, NAT, rotas
│   ├── eks/             # cluster + managed node group (LabRole)
│   ├── ecr/             # 4 repositórios + lifecycle policy
│   ├── rds/             # 2 PostgreSQL + Secrets Manager + backups
│   ├── dynamodb/        # tabela de voluntários + PITR
│   ├── sqs/             # fila de doações + DLQ
│   ├── elasticache/     # opcional (desligado por FinOps)
│   ├── finops/          # AWS Budgets + Cost Anomaly Detection
│   ├── dr-backup/       # bucket S3 cross-region do Velero
│   ├── k8s-bootstrap/   # namespaces, secrets, configmaps, ingress-nginx
│   └── argocd/          # ArgoCD + Applications
└── dr/                  # root module do Warm Standby (mesmos módulos)
```

Nenhum recurso é criado pelo console. Nenhuma IAM Role é criada (restrição do
AWS Academy: usa-se a `LabRole` existente).

### 3.4 CI/CD e DevSecOps

`.github/workflows/_reusable-cicd.yml` é chamado uma vez por serviço:

1. **Build & Unit Test** — `go build`/`go test`, `pip install`/`pytest`.
2. **Lint** — `gofmt` + `go vet` (Go), `flake8` (Python).
3. **Security** — **SCA** com Trivy filesystem + **SAST** com `gosec` (Go) e
   `bandit` (Python). Severidade CRITICAL/HIGH **bloqueia** o pipeline.
4. **Docker** — build, scan da imagem com Trivy, push no ECR com tag
   `v1.0.0-<sha>`.
5. **GitOps** — commit que atualiza a tag da imagem no manifesto.

### 3.5 GitOps (ArgoCD)

O ArgoCD observa `gitops/` com `automated.prune` e `selfHeal` ligados. O
commit do passo 5 é o único gatilho de deploy — **não existe `kubectl apply`
de aplicação em lugar nenhum**. Um `kubectl edit` manual no cluster é
revertido pelo `selfHeal` em segundos.

Applications registradas: `ngo`, `donation`, `volunteer`,
`solidarytech-ingress`, `observability-stack` (app-of-apps),
`self-healing-webhook` e, sob a observabilidade, `kube-prometheus-stack`,
`loki`, `opentelemetry-collector`, `datadog` e `velero`.

### 3.6 Observabilidade e APM

- **OpenTelemetry Collector** (DaemonSet) é a peça central: recebe OTLP dos
  três serviços e roteia os três sinais — traces para o Datadog, métricas
  para o Prometheus, logs para o Loki (e Datadog).
- **Instrumentação**: `services/_shared/telemetry.py` (Python, auto-instrumenta
  Flask, requests, psycopg2, botocore e logging) e
  `services/donation-service/telemetry/` (Go, `otelhttp` + métricas OTel).
- **Distributed tracing**: propagação W3C `traceparent`. No `donation-service`
  o contexto do trace é injetado nos `MessageAttributes` da mensagem SQS, de
  forma que qualquer consumidor futuro continue o mesmo trace.
- **Métricas de negócio/SLI** com nomes estáveis em todos os serviços:
  `http_requests_total` e `http_request_duration_seconds` (histograma em
  segundos), com labels `service`, `http_request_method`, `http_route` e
  `http_response_status_code`.

---

## 4. Camada Fase 5

| Frente | Onde está implementado |
|---|---|
| SRE — SLI/SLO/Error Budget | `gitops/base/observability/05-prometheus-rules.yaml`, painel `07-grafana-dashboard-sre-slo.yaml`, doc [SRE-SLO-SLI-SLA.md](SRE-SLO-SLI-SLA.md) |
| FinOps — tags, rightsizing, forecast | `terraform/variables.tf` + `providers.tf` (tags), `gitops/base/*/deployment.yaml` (requests/limits), `terraform/modules/finops/` (Budgets + anomalias), doc [FINOPS.md](FINOPS.md) |
| ITSM / AIOps | Alertmanager → PagerDuty → Discord, self-healing webhook, Datadog Watchdog, doc [ITSM-AIOPS.md](ITSM-AIOPS.md) |
| Segurança e DR | Velero cross-region (`08-velero.yaml` + `modules/dr-backup`), Warm Standby (`terraform/dr/`), doc [PCN-DR.md](PCN-DR.md) |

---

## 5. Decisões de arquitetura e trade-offs

| Decisão | Alternativa descartada | Motivo |
|---|---|---|
| Namespace por serviço | Namespace único | Isolamento de Secrets e blast radius menor; custo zero |
| Métricas HTTP próprias (`http_requests_total`) | Convenção semântica do OTel | Os nomes do OTel mudaram entre versões; nomes estáveis mantêm SLO, alertas e painéis coerentes |
| ElastiCache desligado | Provisionar "por garantia" | Nenhum serviço usa cache hoje; recurso ocioso é desperdício puro (~US$ 12/mês) |
| PAY_PER_REQUEST no DynamoDB | Capacidade provisionada | Tráfego imprevisível (picos de mídia); provisionar para o pico desperdiça no vale |
| Velero sem snapshot de volume | File System Backup | Não há PVC: os dados vivem em RDS e DynamoDB, ambos com backup nativo |
| Credenciais AWS via Secret | IRSA | AWS Academy não permite criar IAM Role/OIDC. Risco aceito e registrado no PCN |
| Warm Standby destruído em repouso | Standby sempre ligado | Duplicaria o custo mensal; o RTO acordado (4 h) comporta o tempo de `apply` |

---

## 6. Fluxo de uma doação (caminho crítico ponta a ponta)

1. `POST /api/donation/donations` chega no NLB → ingress-nginx (rate limit 50 rps).
2. `donation-service` abre o span raiz (`otelhttp`) e registra
   `http_requests_total` / `http_request_duration_seconds`.
3. `INSERT` no RDS `donationdb` dentro do contexto do trace.
4. Publicação assíncrona no SQS com o `traceparent` propagado.
5. Resposta `201` ao doador.
6. Traces vão ao Datadog; métricas ao Prometheus; logs ao Loki.
7. As regras de SLO avaliam a taxa de erro a cada 30s; se o error budget
   começar a queimar 14x acima do previsto, o Alertmanager abre incidente no
   PagerDuty, notifica o Discord **e** aciona o self-healing.
