# SolidaryTech — Hackathon Fase 5 (POSTECH DCLT)

Plataforma de doações e voluntariado da SolidaryTech: **3 microsserviços** em
**AWS EKS**, provisionados por **Terraform**, entregues por **GitOps (ArgoCD)**,
com esteira **DevSecOps** no GitHub Actions, observabilidade completa
(**Prometheus + Loki + Grafana + OpenTelemetry + Datadog APM**) e a camada da
Fase 5: **SRE (SLO/Error Budget)**, **FinOps**, **ITSM/AIOps** e
**Disaster Recovery**.

> Projeto evolutivo: aplica ao novo ecossistema toda a base tecnológica das
> Fases 1 a 4 (o repositório da Fase 4 — ToggleMaster — foi usado como modelo).
> Executado no **AWS Academy**, usando a `LabRole` existente — o Terraform não
> cria nenhuma IAM Role ou Policy.

---

## Arquitetura

```
Internet → NLB → ingress-nginx → ┬→ ngo-service (Python)        → RDS ngodb
                                 ├→ donation-service (Go) ★HOT  → RDS donationdb + SQS
                                 └→ volunteer-service (Python)  → DynamoDB

Telemetria (OTLP) → OTel Collector ─┬→ Datadog APM (traces + Watchdog/AIOps)
                                    ├→ Prometheus (métricas + regras de SLO)
                                    └→ Loki (logs)
                                            ↓
                                        Grafana (painel SRE: SLO/Error Budget)
                                            ↓
                                       Alertmanager
                                            │
                          ┌─────────────────┼─────────────────┐
                          ↓                 ↓                 ↓
                     PagerDuty        Discord          self-healing-webhook
                    (incidente)     (#incidentes)      → rollout restart

DR: Velero → bucket S3 em us-west-2   ·   terraform/dr → Warm Standby em 1 comando
```

Detalhes em [`docs/fase5/ARCHITECTURE.md`](docs/fase5/ARCHITECTURE.md).

---

## Estrutura do repositório

```
.
├── .github/workflows/
│   ├── _reusable-cicd.yml       # esteira DevSecOps (build→lint→SAST/SCA→ECR→GitOps)
│   ├── cicd-services.yml        # orquestra os 3 serviços + self-healing
│   ├── terraform-infra.yml      # provisiona/destrói o ambiente primário
│   └── terraform-dr.yml         # levanta o Warm Standby (DR) em 1 acionamento
├── docs/fase5/
│   ├── ARCHITECTURE.md          # arquitetura e decisões
│   ├── SRE-SLO-SLI-SLA.md       # SLI, SLO, SLA, error budget e MTTR
│   ├── FINOPS.md                # tags, rightsizing, forecast e otimizações
│   ├── ITSM-AIOPS.md            # ciclo de vida do incidente, Watchdog, runbooks
│   ├── PCN-DR.md                # plano de continuidade, RTO/RPO, segurança
│   ├── GUIA-EXECUCAO.md         # passo a passo do zero ao ar
│   ├── ROTEIRO-VIDEO.md         # roteiro minutado do vídeo de 20 min
│   ├── RELATORIO.md / .pdf      # relatório de entrega
│   └── evidencias/              # prints para o relatório
├── gitops/
│   ├── base/
│   │   ├── ngo/ donation/ volunteer/   # Deployment, Service, HPA, Job, PDB
│   │   ├── ingress/                    # NLB → ingress-nginx → serviços
│   │   ├── observability/              # Prometheus, Loki, OTel, Datadog, SLO, painéis, Velero
│   │   └── self-healing/               # webhook de recuperação automática
│   └── templates/                      # Alertmanager com placeholders (sem segredo no Git)
├── services/
│   ├── _shared/telemetry.py     # instrumentação OTel (fonte da verdade, Python)
│   ├── ngo-service/             # Flask + PostgreSQL
│   ├── donation-service/        # Go + PostgreSQL + SQS (Hot Path)
│   ├── volunteer-service/       # Flask + DynamoDB
│   ├── self-healing-webhook/    # pod que executa rollout restart
│   ├── docker-compose.yaml      # ambiente local com LocalStack
│   └── Makefile                 # sync-telemetry, test, up, down
└── terraform/
    ├── main.tf, variables.tf…   # ambiente primário (us-east-1)
    ├── modules/                 # networking, eks, ecr, rds, dynamodb, sqs,
    │                            # elasticache, finops, dr-backup, k8s-bootstrap, argocd
    └── dr/                      # Warm Standby (us-west-2) — mesmos módulos
```

---

## Início rápido

```bash
# 1) Ambiente local (sem custo AWS)
cd services && docker compose up --build
curl localhost:8081/health && curl localhost:8082/health && curl localhost:8083/health

# 2) Nuvem: configurar os secrets do repositório e rodar os workflows
#    Actions → Terraform Infra      → action: apply
#    Actions → CI/CD Microservices  → force_all: true
```

Passo a passo completo (secrets, validação, evidências, teardown):
[`docs/fase5/GUIA-EXECUCAO.md`](docs/fase5/GUIA-EXECUCAO.md).

---

## Checklist dos requisitos da Fase 5

### 0. Fundação DevOps (Fases 1–4)

- [x] Dockerfiles multi-stage otimizados, usuário não-root, para os 3 serviços
- [x] Deploy em Kubernetes (EKS) com requests/limits, probes, HPA e PDB
- [x] IaC completa em Terraform: VPC, EKS, RDS, DynamoDB, SQS, ECR, S3
- [x] CI/CD com testes, SAST (`gosec`/`bandit`) e SCA (Trivy) bloqueantes
- [x] GitOps com ArgoCD (`prune` + `selfHeal`) — zero `kubectl apply` de aplicação
- [x] Observabilidade: Prometheus, Grafana, Loki, OpenTelemetry Collector
- [x] APM Datadog com Distributed Tracing (inclusive propagação via SQS)

### 1. SRE

- [x] Dois SLIs do `donation-service` baseados nas Golden Metrics (erros e latência)
- [x] SLO de 99,9% (disponibilidade) e p95 < 500 ms (latência) + SLA de 99,5%
- [x] Dashboard dedicado a SLO e consumo de Error Budget
- [x] Alertas por taxa de queima (multi-window, multi-burn-rate)
- [x] MTTR evidenciado por camada de detecção, notificação e correção automática

### 2. FinOps

- [x] Tags obrigatórias `Project=SolidaryTech`, `Environment=Production`, `CostCenter=NGO-Core` aplicadas por IaC em duas camadas
- [x] Rightsizing de requests/limits com baseline medido + node group de 4 → 3
- [x] Forecast mensal e anual, com cenários de pico e de desastre
- [x] Recomendação principal (Compute Savings Plan) + 9 otimizações adicionais
- [x] Guardrails automáticos: AWS Budgets (com alerta `FORECASTED`) e Cost Anomaly Detection

### 3. ITSM e AIOps

- [x] Datadog Watchdog para detecção de anomalias sem limiar
- [x] Ciclo de vida do incidente desenhado, da detecção ao post-mortem
- [x] Matriz de severidade, plano de comunicação e runbooks
- [x] Resposta automática (self-healing) com RBAC mínimo e rate limit

### 4. Multicloud, Segurança e DR

- [x] PCN com BIA, RTO/RPO por componente e cenários de desastre
- [x] **Opção A** — Velero com backup cross-region (us-west-2), agendamento horário do Hot Path
- [x] **Opção B** — Terraform modularizado levantando o Warm Standby com 1 comando
- [x] Procedimento de failover e failback, plano de testes (game day semestral)
- [x] Controles de segurança e riscos aceitos documentados

---

## Documentação

| Documento | Conteúdo |
|---|---|
| [ARCHITECTURE.md](docs/fase5/ARCHITECTURE.md) | Visão macro, serviços, fundação DevOps, decisões e trade-offs |
| [SRE-SLO-SLI-SLA.md](docs/fase5/SRE-SLO-SLI-SLA.md) | SLI, SLO, SLA, error budget, burn rate, dashboard e MTTR |
| [FINOPS.md](docs/fase5/FINOPS.md) | Tagueamento, guardrails, rightsizing, forecast e otimizações |
| [ITSM-AIOPS.md](docs/fase5/ITSM-AIOPS.md) | Watchdog, ciclo de vida do incidente, severidades, runbooks |
| [PCN-DR.md](docs/fase5/PCN-DR.md) | BIA, RTO/RPO, Velero, Warm Standby, failover, segurança |
| [GUIA-EXECUCAO.md](docs/fase5/GUIA-EXECUCAO.md) | Do zero ao ar, com validação e solução de problemas |
| [ROTEIRO-VIDEO.md](docs/fase5/ROTEIRO-VIDEO.md) | Roteiro minutado do vídeo de 20 minutos |

---

## Licença

Projeto acadêmico — FIAP / POSTECH.
