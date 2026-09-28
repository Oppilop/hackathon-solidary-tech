# Relatório de Entrega — Hackathon Fase 5

**POSTECH DCLT — DevOps, Cloud e Live Tech**
**Projeto:** SolidaryTech — Plataforma de Doações e Voluntariado

---

## 1. Identificação do grupo

| Nome completo | RM | Username (GitHub / Discord) |
|---|---|---|
| Vitor Gramacho | RM369818 |
| Nicole Polippo | RM369731 |

## 2. Links da entrega

| Item | Link |
|---|---|
| Repositório de código | `https://github.com/Oppilop/hackathon-solidary-tech` |
| Vídeo de demonstração (≤ 20 min) | `SolidaryTech.mp4` |

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

> Grafana, painel "SolidaryTech — SRE: SLO & Error Budget": disponibilidade
> 7d, **gauge de error budget restante**, fator de queima com cortes em 6x e
> 14,4x, e as Golden Metrics.

> <img width="2536" height="1238" alt="image" src="https://github.com/user-attachments/assets/521d27d9-f89c-4884-8dac-db549750e737" />
 <img width="2186" height="1080" alt="image" src="https://github.com/user-attachments/assets/f0e13c99-eb83-4972-8176-e56845b68b8b" />



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

<img width="2186" height="988" alt="image" src="https://github.com/user-attachments/assets/55e6f087-369e-4ff9-a7e6-846184811e81" />


### 5.2 Rightsizing

| Serviço | Baseline medido | requests | limits | HPA |
|---|---|---|---|---|
| `ngo-service` | ~40m / ~90Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% |
| `donation-service` | ~60m / ~110Mi (pico 280m) | 150m / 192Mi | 500m / 384Mi | **2–8 @65%** |
| `volunteer-service` | ~35m / ~85Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% |

Node group reduzido de 4 para **3 × t3.medium** (−US$ 30,37/mês) e
ElastiCache **não provisionado** por ausência de consumidor (−US$ 12,41/mês).

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

Detalhamento em [FINOPS.md](FINOPS.md).

---

## 6. Seção ITSM/AIOps

### 6.1 AIOps — Datadog Watchdog

Ativado sobre `env:production`, com *Unified Service Tagging* (`DD_ENV`,
`DD_SERVICE`, `DD_VERSION`) em todos os deployments e APM alimentado pelo OTel
Collector. Detecta desvio comportamental **sem limiar configurado** — pega o
que nenhuma regra previu.

> Watchdog → Insights com detecção automática.
<img width="2024" height="940" alt="image" src="https://github.com/user-attachments/assets/655d2c02-77fc-4e5e-94fb-2d47274a7daf" />


> Service Map com os 3 serviços e dependências (RDS, SQS, DynamoDB).
> Trace distribuído de `POST /donations`, com o span de publicação no SQS
> (traceparent propagado nos `MessageAttributes`).
> <img width="2164" height="1088" alt="image" src="https://github.com/user-attachments/assets/c599091a-6053-43f0-8a0b-bcd10666af2e" />


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

<img width="1600" height="499" alt="image" src="https://github.com/user-attachments/assets/5cc6c073-3aa8-4fe6-917a-456661426a1d" />


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

> `velero schedule get` e `velero backup get`.
> <img width="2112" height="322" alt="image" src="https://github.com/user-attachments/assets/cb40cd22-6760-4aac-ace9-5759ee801e00" />

> Objetos no bucket da região secundária.
<img width="1576" height="98" alt="image" src="https://github.com/user-attachments/assets/893a976d-cb20-43a9-8333-701ea79d2ae1" />

> Workflow do Warm Standby com o `failover_checklist`.
<img width="2146" height="680" alt="image" src="https://github.com/user-attachments/assets/ca784a12-3f58-48cb-ad14-25f4eb83b4ca" />


### 7.3 Segurança

Bancos em subnets privadas; criptografia em repouso em RDS, DynamoDB, S3 e
ECR; nenhuma credencial versionada (PagerDuty e Discord como placeholders
substituídos em tempo de deploy); esteira com Trivy, `gosec` e `bandit`
bloqueando CRITICAL/HIGH; containers não-root com `capabilities.drop: [ALL]`;
self-healing com RBAC mínimo restrito por regex de namespace.

**Riscos aceitos** (limitações do AWS Academy, com correção documentada para
conta própria): credenciais estáticas em Secret no lugar de IRSA, RDS
single-AZ, Prometheus em `emptyDir`, ausência de WAF/TLS no ingress.

> Job de Security Scan com Trivy/gosec/bandit — e um run bloqueado por CRITICAL.
<img width="2014" height="1202" alt="image" src="https://github.com/user-attachments/assets/fa51ac5d-1515-41d8-899c-b203f825d5b8" />

---

## 8. Evidências da fundação (Fases 1 a 4)

>  Pipeline de IaC concluído
> <img width="1600" height="630" alt="image" src="https://github.com/user-attachments/assets/cceabd2f-3345-4058-a39f-69bde68468dc" />

> Applications `Synced/Healthy`
> <img width="1600" height="639" alt="image" src="https://github.com/user-attachments/assets/a0ba479d-9d15-4271-8aef-b5a43724390e" />

> Esteira dos 4 jobs
> <img width="1600" height="705" alt="image" src="https://github.com/user-attachments/assets/f7a927ed-e1f2-4d93-8f14-d35a75b06024" />

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
