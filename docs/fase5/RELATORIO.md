# Relatório de Entrega — Hackathon Fase 5

**POSTECH DCLT — DevOps, Cloud e Live Tech**
**Projeto:** SolidaryTech — Plataforma de Doações e Voluntariado

---

## 1. Identificação do grupo

| Nome completo | RM | Username (GitHub / Discord) |
|---|---|---|
| _preencher_ | _RM_____ | _@usuario_ |
| _preencher_ | _RM_____ | _@usuario_ |
| _preencher_ | _RM_____ | _@usuario_ |
| _preencher_ | _RM_____ | _@usuario_ |
| _preencher_ | _RM_____ | _@usuario_ |

## 2. Links da entrega

| Item | Link |
|---|---|
| Repositório de código | `https://github.com/_SEU-USUARIO_/togglemaster-tc5` |
| Vídeo de demonstração (≤ 20 min) | `https://_____` |
| Código-fonte base dos microsserviços | https://github.com/dougls/hackathon-DCLT |

---

## 3. Sumário executivo

A SolidaryTech ganhou visibilidade nacional e passou a enfrentar picos de
acesso imprevisíveis. A diretoria colocou três exigências: **as doações não
podem parar se a nuvem cair**, **o custo precisa ser justificado centavo a
centavo** e **os incidentes precisam ser descobertos antes do doador**.

A entrega responde às três com evidências operando:

| Pergunta da diretoria | Resposta | Onde comprovar |
|---|---|---|
| Se a nuvem cair, as doações param? | **Não.** RTO de 4 h e RPO de 5 min, com backup cross-region (Velero) e ambiente espelho que sobe com um comando | [§7](#7-seção-segurança-e-dr) |
| Quanto custa e por quê? | **≈ US$ 263/mês**, 100% atribuído por `CostCenter`, com teto, alerta preditivo e economia identificada de **US$ 306/ano** | [§5](#5-seção-finops) |
| Descobrimos antes do doador? | **Sim.** Alerta por taxa de queima do error budget (< 2 min) + Watchdog (AIOps) + correção automática em ~30 s | [§4](#4-seção-sre) e [§6](#6-seção-itsmaiops) |

Toda a base das Fases 1 a 4 foi aplicada ao novo ecossistema: Docker,
Kubernetes, Terraform, CI/CD DevSecOps, GitOps e observabilidade com APM.
**Não há deploy manual via `kubectl`, não há infraestrutura clicada no console
e não há voo cego.**

---

## 4. Seção SRE

### 4.1 Definição formal — `donation-service` (Hot Path)

| | **SLI #1 — Disponibilidade** | **SLI #2 — Latência** |
|---|---|---|
| **Definição** | Proporção de requisições HTTP respondidas sem erro de servidor (5xx) | Proporção de requisições atendidas em menos de 500 ms |
| **Golden Metric** | Errors | Latency |
| **Fonte** | `http_requests_total` (OpenTelemetry, instrumentado no serviço) | `http_request_duration_seconds` (histograma) |
| **Exclusões** | `/health` e `/metrics` | idem |
| **SLO** | **99,9%** | **95% < 500 ms (p95)** |

**SLA com as ONGs parceiras:** disponibilidade mensal de **99,5%** e p95 de
**1.000 ms**, com créditos de serviço de 10% / 25% / 50% conforme a faixa de
descumprimento. A folga entre SLO (99,9%) e SLA (99,5%) é a margem de correção.

### 4.2 Error Budget

| Janela | Orçamento de erro (0,1%) |
|---|---|
| 30 dias | **43 min 12 s** |
| 7 dias | **10 min 05 s** |
| 24 horas | **1 min 26 s** |

Política: acima de 50% do budget → operação normal; entre 0% e 25% → metade da
capacidade do time em confiabilidade; **budget zerado → congelamento de
features**, disparado automaticamente pelo alerta
`DonationErrorBudgetExhausted`.

### 4.3 Alertas por taxa de queima

| Alerta | Condição (multi-janela) | Severidade | Ação |
|---|---|---|---|
| `DonationErrorBudgetFastBurn` | queima > 14,4x em 5m **e** 1h | critical | PagerDuty + **self-healing automático** |
| `DonationErrorBudgetSlowBurn` | queima > 6x em 30m **e** 6h | warning | Ticket |
| `DonationErrorBudgetExhausted` | budget ≤ 0 em 7 dias | critical | Congelamento de features |
| `DonationLatencySLOBreach` | p95 > 500 ms por 5 min | warning | Ticket |

### 4.4 Dashboard SRE

> **📷 Evidência 01** — `evidencias/01-dashboard-sre-slo.png`
> Grafana, painel "SolidaryTech — SRE: SLO & Error Budget": disponibilidade
> 7d, **gauge de error budget restante**, fator de queima com cortes em 6x e
> 14,4x, e as Golden Metrics.

> **📷 Evidência 02** — `evidencias/02-prometheus-regras-slo.png`
> Prometheus → Alerts, com as regras de burn rate carregadas.

### 4.5 MTTR

| Etapa | Sem a stack | Com a stack |
|---|---|---|
| Detectar | horas (reclamação da ONG) | **< 2 min** (regra avaliada a cada 30 s) |
| Notificar | manual | segundos (PagerDuty + Discord) |
| Diagnosticar | dezenas de minutos | **< 5 min** (trace no APM + log correlacionado) |
| Corrigir | ~15 min (humano) | **~30 s** (self-healing) |
| Confirmar | manual | automático (`send_resolved`) |

**MTTR estimado para a falha mais comum: menos de 5 minutos, sem intervenção
humana.** Detalhamento em [SRE-SLO-SLI-SLA.md](SRE-SLO-SLI-SLA.md).

---

## 5. Seção FinOps

### 5.1 Estratégia de tagueamento (em IaC)

| Tag | Valor |
|---|---|
| `Project` | `SolidaryTech` |
| `Environment` | `Production` |
| `CostCenter` | `NGO-Core` |
| `Owner`, `ManagedBy`, `Phase`, `Criticality`, `DR` | complementares |

Aplicadas em **duas camadas**: `default_tags` no provider AWS (pega qualquer
recurso, mesmo esquecido) e `merge()` explícito em cada módulo (torna a
intenção auditável no `terraform plan`).

> **📷 Evidência 03** — `evidencias/03-tags-tag-editor.png`
> AWS Tag Editor filtrando `Project = SolidaryTech`.

> **📷 Evidência 04** — `evidencias/04-cost-explorer-costcenter.png`
> Cost Explorer agrupado por tag `CostCenter`.

### 5.2 Rightsizing

| Serviço | Baseline medido | requests | limits | HPA |
|---|---|---|---|---|
| `ngo-service` | ~40m / ~90Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% |
| `donation-service` | ~60m / ~110Mi (pico 280m) | 150m / 192Mi | 500m / 384Mi | **2–8 @65%** |
| `volunteer-service` | ~35m / ~85Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% |

Node group reduzido de 4 para **3 × t3.medium** (−US$ 30,37/mês) e
ElastiCache **não provisionado** por ausência de consumidor (−US$ 12,41/mês).

> **📷 Evidência 05** — `evidencias/05-rightsizing-uso-vs-request.png`
> Painel "FinOps — uso real vs. request declarado".

### 5.3 Forecast mensal

| Componente | US$/mês |
|---|---:|
| EKS control plane | 73,00 |
| EC2 — 3 × t3.medium | 91,10 |
| RDS — 2 × db.t3.micro + storage | 30,88 |
| NAT Gateway (horas + dados) | 35,55 |
| NLB (horas + LCU) | 20,93 |
| EBS dos nodes | 4,80 |
| DynamoDB, SQS, ECR, S3, Secrets Manager | 4,48 |
| Transferência de dados e CloudWatch | 2,50 |
| **TOTAL** | **≈ 263,24** |

**Projeção anual: ≈ US$ 3.158,88.** Cenário de pico de mídia (7 dias):
≈ US$ 285,77. Failover ativo por 3 dias: +US$ 30 pontuais. Ferramentas SaaS
(Datadog *For Education*, PagerDuty *Developer*, Discord): US$ 0.

### 5.4 Recomendação de otimização

**Principal — Compute Savings Plan de 1 ano, sem entrada, para a base fixa de
3 nodes:** desconto típico de 28% sobre US$ 91,10/mês →
**economia de US$ 25,51/mês (US$ 306,12/ano)**, sem alterar código,
arquitetura ou tipo de instância. O excedente dos picos continua On-Demand.

Complementares: Graviton `t4g.medium` (−US$ 17,52/mês), VPC Gateway Endpoints
para S3/DynamoDB, GSI no DynamoDB para eliminar o `Scan`. Já implementadas:
lifecycle no ECR e no bucket de backup, e ambiente de DR destruído em repouso.

> **📷 Evidência 06** — `evidencias/06-aws-budgets.png`
> AWS Budgets com os alertas de 80% (real), 100% (real) e 100% (**previsto**).

Detalhamento em [FINOPS.md](FINOPS.md).

---

## 6. Seção ITSM/AIOps

### 6.1 AIOps — Datadog Watchdog

Ativado sobre `env:production`, com *Unified Service Tagging* (`DD_ENV`,
`DD_SERVICE`, `DD_VERSION`) em todos os deployments e APM alimentado pelo OTel
Collector. Detecta desvio comportamental **sem limiar configurado** — pega o
que nenhuma regra previu.

> **📷 Evidência 07** — `evidencias/07-datadog-watchdog.png`
> Watchdog → Insights com detecção automática.

> **📷 Evidência 08** — `evidencias/08-datadog-service-map.png`
> Service Map com os 3 serviços e dependências (RDS, SQS, DynamoDB).

> **📷 Evidência 09** — `evidencias/09-datadog-trace-sqs.png`
> Trace distribuído de `POST /donations`, com o span de publicação no SQS
> (traceparent propagado nos `MessageAttributes`).

### 6.2 Ciclo de vida do incidente

```
1. DETECÇÃO      Watchdog (AIOps) │ burn rate │ alertas de infra
2. TRIAGEM       Alertmanager: group_by + inhibit_rules + roteamento por severidade
3a. AUTOMÁTICO   auto_heal=true → self-healing-webhook → rollout restart (rate limit 5 min)
3b. HUMANO       PagerDuty (plantão) → Discord #incidentes → stakeholders
4. DIAGNÓSTICO   Painel SRE → trace no APM → log correlacionado por trace_id (Loki)
5. MITIGAÇÃO     Rollback por GitOps │ escala do HPA │ hotfix — sempre por commit
6. RESOLUÇÃO     Janela curta resolve → send_resolved fecha o incidente
7. PÓS-INCIDENTE Post-mortem sem culpados → débito do error budget → ações viram issues
```

Matriz de severidade P1–P4, plano de comunicação por público e runbooks
completos em [ITSM-AIOPS.md](ITSM-AIOPS.md).

> **📷 Evidência 10** — `evidencias/10-pagerduty-incidente.png`
> **📷 Evidência 11** — `evidencias/11-discord-notificacao.png`
> **📷 Evidência 12** — `evidencias/12-self-healing-log.png`
> Log JSON do webhook registrando o `rollout restart` automático.

---

## 7. Seção Segurança e DR

### 7.1 PCN — RTO e RPO

| Componente | RTO | RPO | Mecanismo |
|---|---|---|---|
| **Doações (dados)** | **4 h** | **5 min** | Backup automático do RDS + PITR (7 dias) |
| **Doações (serviço)** | **4 h** | — | Warm Standby + restore do Velero |
| Voluntários (DynamoDB) | 4 h | 5 min | Point-in-Time Recovery (35 dias) |
| Cadastro de ONGs | 8 h | 24 h | Backup automático do RDS |
| Estado do cluster | 2 h | **1 h** | Velero (backup horário do Hot Path) |
| Infraestrutura | 1 h | **0** | Terraform versionado |
| Aplicações | 15 min | **0** | GitOps |

Análise de impacto (BIA), 8 cenários de desastre, procedimento de failover
passo a passo (≈ 2 h 45 min, dentro do RTO de 4 h), failback e plano de testes
com game day semestral em [PCN-DR.md](PCN-DR.md).

### 7.2 Estratégia de DR — as duas opções

**Opção A — Velero (backup cross-region).** Bucket S3 em **us-west-2**,
versionado e criptografado; backup diário completo (TTL 30 dias) e **backup
horário do `donation-namespace`** (TTL 7 dias). Credenciais em Secret criado
pelo Terraform — nunca no Git. Ciclo de vida move para STANDARD_IA em 30 dias.

**Opção B — Warm Standby ativo-passivo.** `terraform/dr/` reutiliza os
**mesmos módulos** do primário, mudando apenas região, state e tamanho do node
group, e apontando para o **mesmo repositório GitOps** — sem manifestos
duplicados. Sobe com um comando (`terraform -chdir=terraform/dr apply`) ou pelo
workflow **Terraform DR**. Em repouso fica destruído: **custo zero**.

> **📷 Evidência 13** — `evidencias/13-velero-backups.png`
> `velero schedule get` e `velero backup get`.
> **📷 Evidência 14** — `evidencias/14-s3-backup-us-west-2.png`
> Objetos no bucket da região secundária.
> **📷 Evidência 15** — `evidencias/15-terraform-dr-apply.png`
> Workflow do Warm Standby com o `failover_checklist`.

### 7.3 Segurança

Bancos em subnets privadas; criptografia em repouso em RDS, DynamoDB, S3 e
ECR; nenhuma credencial versionada (PagerDuty e Discord como placeholders
substituídos em tempo de deploy); esteira com Trivy, `gosec` e `bandit`
bloqueando CRITICAL/HIGH; containers não-root com `capabilities.drop: [ALL]`;
self-healing com RBAC mínimo restrito por regex de namespace.

**Riscos aceitos** (limitações do AWS Academy, com correção documentada para
conta própria): credenciais estáticas em Secret no lugar de IRSA, RDS
single-AZ, Prometheus em `emptyDir`, ausência de WAF/TLS no ingress.

> **📷 Evidência 16** — `evidencias/16-pipeline-devsecops.png`
> Job de Security Scan com Trivy/gosec/bandit — e um run bloqueado por CRITICAL.

---

## 8. Evidências da fundação (Fases 1 a 4)

> **📷 Evidência 17** — `evidencias/17-terraform-apply.png` — pipeline de IaC concluído
> **📷 Evidência 18** — `evidencias/18-argocd-applications.png` — Applications `Synced/Healthy`
> **📷 Evidência 19** — `evidencias/19-cicd-pipeline-verde.png` — esteira dos 4 jobs
> **📷 Evidência 20** — `evidencias/20-dashboard-visao-geral.png` — painel de visão geral (Golden Metrics + FinOps)
> **📷 Evidência 21** — `evidencias/21-loki-logs.png` — logs centralizados no Grafana
> **📷 Evidência 22** — `evidencias/22-pods-namespaces.png` — `kubectl get pods -A`

---

## 9. Conclusão

A plataforma da SolidaryTech deixou de ser "uma aplicação que faz deploy
automático" e passou a ter **maturidade operacional demonstrável**:

- **Confiabilidade com contrato:** SLI, SLO, SLA e error budget definidos,
  medidos em painel próprio e ligados a uma política de congelamento acordada
  antes do incidente.
- **Custo com dono:** 100% dos recursos tagueados por IaC, forecast de
  US$ 263/mês, teto com alerta preditivo, detecção de anomalia e uma
  recomendação de economia de US$ 306/ano sem mudar uma linha de código.
- **Resposta preditiva:** Watchdog para o que ninguém previu, alerta por
  velocidade de queima para o que já está acontecendo, e correção automática
  em ~30 segundos.
- **Continuidade provada:** RTO de 4 h e RPO de 5 min sustentados por backup
  cross-region e por um ambiente espelho que sobe com um comando — e que é
  testado em game day semestral.

O que sustenta tudo isso é uma escolha única, repetida em cada camada:
**nada existe fora do Git**. Infraestrutura, manifestos, regras de SLO,
dashboards, política de tags e plano de DR são código revisável, versionado e
reproduzível — em qualquer região, a qualquer momento.
