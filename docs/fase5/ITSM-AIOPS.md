# ITSM e AIOps — Gestão Preditiva de Incidentes

> Objetivo: **o incidente deve ser detectado antes de o doador perceber**, e a
> primeira tentativa de correção deve acontecer sem esperar um humano acordar.

---

## 1. AIOps — detecção comportamental

### 1.1 Datadog Watchdog

O Watchdog é o motor de IA do Datadog: ele aprende o comportamento normal de
cada serviço (latência, taxa de erro, throughput, uso de recursos) e sinaliza
desvios **sem que exista um limiar configurado**. É o complemento necessário
aos alertas baseados em regra — regras só pegam o que alguém previu.

**Pré-requisitos já atendidos pela plataforma:**

| Requisito do Watchdog | Onde está garantido |
|---|---|
| APM recebendo traces | OTel Collector exporta para o Datadog (`03-otel-collector.yaml`, pipeline `traces`) |
| *Unified Service Tagging* (`env`, `service`, `version`) | Labels `tags.datadoghq.com/*` + envs `DD_ENV`/`DD_SERVICE`/`DD_VERSION` em todos os deployments |
| Infra metrics do cluster | Datadog Agent (DaemonSet) + `orchestratorExplorer` habilitado (`04-datadog.yaml`) |
| Tags de negócio | `project:SolidaryTech`, `costcenter:NGO-Core`, `env:production` |

**Ativação (feita na UI do Datadog — o Watchdog não é configurável por Helm):**

1. `APM → Services` → confirmar que `donation-service`, `ngo-service` e
   `volunteer-service` aparecem com traces.
2. `Watchdog → Watchdog Alerts` → **Create Watchdog Alert**.
3. Escopo: `env:production AND service:donation-service`.
4. Tipos de detecção: *Errors*, *Latency* e *Anomalous behavior*.
5. Notificação: integração com o PagerDuty (mesmo serviço usado pelo
   Alertmanager, para que Watchdog e regras caiam na mesma fila de incidentes).
6. `Watchdog → Insights` fica disponível automaticamente e é onde se evidencia
   a detecção sem configuração prévia.

> **Evidência para o vídeo:** capturar a tela `Watchdog → Insights` mostrando
> um insight detectado automaticamente e a `Service Map` com os 3 serviços e
> suas dependências (RDS, SQS, DynamoDB).

### 1.2 Camadas de detecção — o que cada uma pega

| Camada | Tecnologia | Pega o quê | Latência de detecção |
|---|---|---|---|
| **Preditiva** | Datadog Watchdog | Desvio de comportamento sem limiar (ex.: p95 subindo 3x acima do padrão do horário) | minutos, antes do impacto |
| **Preditiva** | Alerta de **burn rate lento** (6x) | Degradação crônica que ainda não violou nada | 30 min – 6 h |
| **Reativa** | Alerta de **burn rate rápido** (14,4x) | Queima aguda de error budget | < 2 min |
| **Reativa** | `ServiceDown`, `PodCrashLooping`, saturação | Falha dura de infraestrutura | 2–5 min |
| **Financeira** | Cost Anomaly Detection | Desvio de gasto (muitas vezes o *sintoma* de um bug: retry infinito, scan descontrolado) | diária |

A camada financeira não é decorativa: um loop de retry no `donation-service`
aparece primeiro como pico de custo no SQS/DynamoDB.

---

## 2. Ciclo de vida do incidente (ITSM)

```
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 1. DETECÇÃO                                                          │
   │    Watchdog (AIOps) │ PrometheusRule (burn rate) │ Alerta de infra    │
   └───────────────────────────────┬──────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 2. TRIAGEM E CLASSIFICAÇÃO — Alertmanager                            │
   │    group_by [alertname, namespace, service] → 1 incidente, não 8     │
   │    inhibit_rules: crítico silencia warnings do mesmo namespace       │
   │    Roteamento por severity → P1 (critical) ou P3 (warning)           │
   └───────────────┬──────────────────────────────────┬───────────────────┘
                   ▼                                  ▼
   ┌───────────────────────────────┐   ┌──────────────────────────────────┐
   │ 3a. RESPOSTA AUTOMÁTICA       │   │ 3b. NOTIFICAÇÃO HUMANA           │
   │  auto_heal="true"             │   │  PagerDuty abre incidente        │
   │  → self-healing-webhook       │   │  → aciona plantão (P1)           │
   │  → kubectl rollout restart    │   │  → Discord #incidentes           │
   │  (rate limit: 1 / 5 min)      │   │  → stakeholders informados       │
   └───────────────┬───────────────┘   └──────────────┬───────────────────┘
                   └──────────────┬───────────────────┘
                                  ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 4. DIAGNÓSTICO                                                       │
   │    Painel SRE: é erro, latência ou saturação?                        │
   │    Datadog APM: qual span está lento/falhando? (trace distribuído)   │
   │    Loki: logs correlacionados pelo trace_id                          │
   └───────────────────────────────┬──────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 5. MITIGAÇÃO / CORREÇÃO                                              │
   │    Rollback via GitOps (revert do commit) │ escalar HPA │ hotfix     │
   │    Nenhuma ação por kubectl: tudo passa por commit (rastreável)      │
   └───────────────────────────────┬──────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 6. RESOLUÇÃO E FECHAMENTO                                            │
   │    Janela curta do alerta resolve → send_resolved fecha o PagerDuty  │
   │    e publica o "resolvido" no Discord                                │
   └───────────────────────────────┬──────────────────────────────────────┘
                                   ▼
   ┌──────────────────────────────────────────────────────────────────────┐
   │ 7. PÓS-INCIDENTE                                                     │
   │    Post-mortem sem culpados (obrigatório para P1 e para qualquer     │
   │    consumo > 20% do error budget)                                    │
   │    Débito do error budget → aciona a política de congelamento        │
   │    Ações viram issues; alerta novo/ajustado vira commit no repo      │
   └──────────────────────────────────────────────────────────────────────┘
```

### 2.1 Matriz de severidade

| Severidade | Critério | Quem é acionado | Prazo de resposta | Comunicação |
|---|---|---|---|---|
| **P1 — Crítico** | Hot Path indisponível ou burn rate > 14,4x; perda de doações | Plantão via PagerDuty (telefone) | 15 min | Discord imediato + e-mail às ONGs em 1 h |
| **P2 — Alto** | Serviço não crítico fora do ar; burn rate 6x sustentado | Squad em horário comercial | 4 h | Discord |
| **P3 — Médio** | Saturação, CrashLoop isolado, latência acima do alvo sem violar SLA | Backlog do próximo dia útil | 1 dia útil | Ticket |
| **P4 — Baixo** | Melhorias, alertas informativos | Backlog | Sprint | — |

### 2.2 Comunicação com stakeholders

| Público | Canal | Quando | Conteúdo |
|---|---|---|---|
| Squad de plataforma | Discord `#incidentes` + PagerDuty | Imediato | Alerta bruto com summary, runbook e link do painel |
| Diretoria da SolidaryTech | E-mail | P1 em até 1 h; resumo semanal | Impacto em doações, previsão de normalização |
| ONGs parceiras | Página de status + e-mail | P1 com impacto > 30 min | Linguagem não técnica, prazo estimado, sem jargão |
| Doadores | Aviso no app | Indisponibilidade percebida | "Estamos com instabilidade, sua doação não foi perdida" |

### 2.3 Post-mortem sem culpados

Obrigatório para todo P1 e para qualquer incidente que consuma mais de 20% do
error budget. Estrutura fixa:

1. **Resumo** — o que aconteceu, em uma frase.
2. **Impacto** — quantas doações afetadas, quanto tempo, quanto de error budget.
3. **Linha do tempo** — detecção → notificação → mitigação → resolução, com
   horários extraídos do PagerDuty e do Grafana.
4. **Causa raiz** — técnica, com o trace/log que comprova.
5. **O que foi bem / o que foi mal** — inclui explicitamente se o self-healing
   ajudou ou mascarou o problema.
6. **Ações** — cada uma com dono e prazo; toda ação vira issue no repositório.

Regra cultural: o documento descreve **sistemas e processos**, nunca pessoas.
Se a conclusão for "fulano errou", o post-mortem está incompleto — a pergunta
certa é por que o sistema permitiu que aquele erro chegasse à produção.

---

## 3. Automação de resposta (self-healing)

`services/self-healing-webhook/` — pod Python com RBAC mínimo
(`apps/deployments: get, list, patch`).

| Proteção | Implementação | Por quê |
|---|---|---|
| Escopo de namespace | `ALLOWED_NAMESPACE_REGEX=^(ngo\|donation\|volunteer)-namespace$` | O webhook não pode tocar em `kube-system` nem no ArgoCD |
| Rate limit | `RATE_LIMIT_SECONDS=300` (1 restart por deployment / 5 min) | Impede loop de restart escondendo a causa raiz |
| RBAC mínimo | ClusterRole só com `get/list/patch` em deployments | Comprometer o pod não dá controle do cluster |
| Container endurecido | `readOnlyRootFilesystem`, `runAsNonRoot` (UID 10001), `drop: [ALL]` | Reduz superfície de ataque |
| Auditoria | Log JSON estruturado, indexado pelo Loki | Toda ação automática fica rastreável no painel SRE |

**Quando o self-healing NÃO deve agir:** falha de dependência externa (RDS
fora do ar) — reiniciar o pod não resolve e ainda apaga o estado de
diagnóstico. Por isso apenas alertas explicitamente marcados com
`auto_heal: "true"` acionam o webhook: hoje, `HighHttpErrorRate` e
`DonationErrorBudgetFastBurn`.

---

## 4. Runbooks

### <a id="runbook-donation-error-budget"></a>Runbook: `DonationErrorBudgetFastBurn`

**Sintoma:** o error budget do Hot Path queima 14x acima do previsto.

1. **Confirmar impacto** — painel SRE: taxa de erro e budget restante.
   Se o tráfego estiver perto de zero, é ruído estatístico → verificar o
   denominador antes de escalar.
2. **Verificar se o self-healing já agiu** — painel "Réplicas prontas vs.
   desejadas" e logs do webhook no Loki.
3. **Correlacionar com deploy** — `kubectl -n argocd get app donation -o wide`
   e o histórico de commits em `gitops/base/donation/`. Deploy nos últimos
   30 min é o suspeito nº 1.
4. **Ver o trace no Datadog** — `APM → donation-service → Errors`. Identificar
   o span que falha: banco, SQS ou a própria aplicação.
5. **Checar dependências** — RDS (conexões, CPU), fila SQS e DLQ.
6. **Mitigar:**
   - Deploy ruim → `git revert` do commit de bump da imagem (o ArgoCD reverte sozinho).
   - Saturação → aumentar `maxReplicas` do HPA via commit.
   - Falha do RDS → seguir o [PCN](PCN-DR.md).
7. **Comunicar** — Discord no início; e-mail à diretoria se passar de 1 h.
8. **Fechar** — confirmar alerta resolvido e abrir o post-mortem.

### <a id="runbook-high-error-rate"></a>Runbook: `HighHttpErrorRate`

**Sintoma:** mais de 5% de 5xx em qualquer um dos três serviços.

1. Identificar o serviço em `{{ $labels.service }}`.
2. `kubectl -n <svc>-namespace get pods` — procurar `CrashLoopBackOff`.
3. Logs no Loki: `{k8s_namespace_name="<svc>-namespace"} |~ "(?i)(error|exception)"`.
4. Causas mais comuns, em ordem: credenciais AWS expiradas (o token do AWS
   Academy dura ~4 h), Secret/ConfigMap ausente, banco inacessível, bug de deploy.
5. Se for o `donation-service`, tratar como P1 e seguir o runbook acima.
6. Se o self-healing já reiniciou 2 vezes sem sucesso, **desabilitar o
   auto_heal do alerta** (commit) para não mascarar o problema, e investigar.
