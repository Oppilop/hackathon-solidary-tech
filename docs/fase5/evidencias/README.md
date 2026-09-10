# Evidências visuais — o que capturar

Salve cada print com **exatamente** o nome abaixo: o `RELATORIO.md` já
referencia esses arquivos, então basta regerar o PDF depois de colocá-los aqui.

> A regra de avaliação do edital é explícita: *"Qualquer requisito que não for
> claramente demonstrado no vídeo ou documentado no relatório sofrerá dedução
> direta de pontos."* Cada print abaixo cobre um requisito.

## Seção SRE

| Arquivo | O que precisa aparecer |
|---|---|
| `01-dashboard-sre-slo.png` | Grafana → "SolidaryTech — SRE: SLO & Error Budget": disponibilidade 7d, **gauge de error budget**, fator de queima |
| `02-prometheus-regras-slo.png` | Prometheus → Alerts, com `DonationErrorBudgetFastBurn` e `SlowBurn` carregadas |

## Seção FinOps

| Arquivo | O que precisa aparecer |
|---|---|
| `03-tags-tag-editor.png` | AWS Tag Editor filtrando `Project = SolidaryTech`, listando os recursos |
| `04-cost-explorer-costcenter.png` | Cost Explorer agrupado por tag `CostCenter` |
| `05-rightsizing-uso-vs-request.png` | Painel "FinOps — uso real vs. request declarado" |
| `06-aws-budgets.png` | AWS Budgets com os 3 alertas (80% real, 100% real, 100% **previsto**) |

## Seção ITSM / AIOps

| Arquivo | O que precisa aparecer |
|---|---|
| `07-datadog-watchdog.png` | Watchdog → Insights com detecção automática |
| `08-datadog-service-map.png` | Service Map com os 3 serviços e dependências (RDS, SQS, DynamoDB) |
| `09-datadog-trace-sqs.png` | Trace de `POST /donations` com o span de publicação no SQS |
| `10-pagerduty-incidente.png` | Incidente aberto no PagerDuty, com a linha do tempo |
| `11-discord-notificacao.png` | Alerta e resolução no canal `#incidentes` |
| `12-self-healing-log.png` | Log JSON do webhook com o `rollout restart` automático |

## Seção Segurança e DR

| Arquivo | O que precisa aparecer |
|---|---|
| `13-velero-backups.png` | `velero schedule get` + `velero backup get` |
| `14-s3-backup-us-west-2.png` | Objetos no bucket da **região secundária** |
| `15-terraform-dr-apply.png` | Workflow "Terraform DR" com o `failover_checklist` |
| `16-pipeline-devsecops.png` | Job de Security Scan (Trivy/gosec/bandit) — de preferência um run **bloqueado** por CRITICAL |

## Fundação (Fases 1 a 4)

| Arquivo | O que precisa aparecer |
|---|---|
| `17-terraform-apply.png` | Workflow "Terraform Infra" com `apply` concluído |
| `18-argocd-applications.png` | Todas as Applications `Synced / Healthy` |
| `19-cicd-pipeline-verde.png` | "CI/CD Microservices" com os 4 jobs verdes |
| `20-dashboard-visao-geral.png` | Painel de visão geral (Golden Metrics + linha de FinOps) |
| `21-loki-logs.png` | Logs centralizados no Grafana via Loki |
| `22-pods-namespaces.png` | `kubectl get pods -A` com os namespaces da plataforma |

---

**Antes de capturar:** confira que nenhuma credencial fica visível na tela
(token do AWS Academy, chave do Datadog, webhook do Discord, senha do ArgoCD).

**Depois de colocar os prints aqui:** regere o PDF a partir do `RELATORIO.md`.
