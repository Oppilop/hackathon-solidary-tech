# SRE — SLI, SLO, SLA e Error Budget

> Serviço sob acordo: **`donation-service`** (Hot Path). É por onde entra o
> dinheiro das ONGs; é o único componente com compromisso formal.

---

## 1. Por que só o donation-service tem SLO

Definir SLO para tudo dilui a atenção da equipe e gera fadiga de alerta. A
regra adotada: **só tem SLO aquilo que, se falhar, dói para o usuário final e
para a ONG parceira**. Uma listagem de ONGs indisponível por 3 minutos é
irritante; uma doação recusada é dinheiro que não chega a quem precisa.

Os demais serviços têm alertas operacionais (erro > 5%, pod em CrashLoop,
saturação de recursos), mas não têm error budget nem política de congelamento.

---

## 2. Definições formais

### 2.1 SLI #1 — Disponibilidade (Golden Metric: *Errors*)

> **Proporção de requisições HTTP ao `donation-service` respondidas sem erro
> do servidor (5xx), medida na borda da aplicação.**

```promql
1 - (
  sum(increase(http_requests_total{service="donation-service",http_response_status_code=~"5.."}[7d]))
  /
  sum(increase(http_requests_total{service="donation-service"}[7d]))
)
```

| Item | Valor |
|---|---|
| Fonte | Métrica `http_requests_total` instrumentada com OpenTelemetry no próprio serviço |
| Numerador | Requisições sem status 5xx |
| Denominador | Todas as requisições HTTP recebidas |
| Exclusões | `/health` e `/metrics` (tráfego de plataforma, não de usuário) |

**SLO:** **99,9%** de disponibilidade na janela móvel.
**Error budget:** 0,1% das requisições — 1 erro a cada 1.000.

### 2.2 SLI #2 — Latência (Golden Metric: *Latency*)

> **Proporção de requisições ao `donation-service` atendidas em menos de
> 500 ms**, e o percentil 95 do tempo de resposta.

```promql
# Proporção "boa"
sum(rate(http_request_duration_seconds_bucket{service="donation-service",le="0.5"}[5m]))
/
sum(rate(http_request_duration_seconds_count{service="donation-service"}[5m]))

# p95
histogram_quantile(0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{service="donation-service"}[5m]))
)
```

**SLO:** **95% das requisições abaixo de 500 ms** (p95 < 500 ms).

Por que 500 ms: o caminho crítico faz um `INSERT` no PostgreSQL e devolve a
resposta; a publicação no SQS é assíncrona e não entra no tempo do doador.
Medições em ambiente de teste ficaram entre 40 ms e 120 ms, então 500 ms é um
alvo com folga real, e não um número inventado para nunca ser violado.

### 2.3 As outras duas Golden Metrics

Não viram SLO, mas são monitoradas no painel e alimentam o diagnóstico:

| Golden Metric | Métrica | Uso |
|---|---|---|
| **Traffic** | `sum(rate(http_requests_total{service="donation-service"}[5m]))` | Contexto: queda de erro com queda de tráfego não é melhora, é ausência de usuários |
| **Saturation** | CPU e memória sobre o `limit`, e réplicas prontas vs. desejadas | Antecipa violação de latência e dispara o HPA |

---

## 3. SLA — o que é prometido às ONGs parceiras

**SLI/SLO são metas internas de engenharia; SLA é o contrato externo.** Por
isso o SLA é deliberadamente mais frouxo que o SLO: a diferença é a margem que
permite corrigir um problema antes de descumprir o contrato.

| Item | SLO (interno) | SLA (contratual) |
|---|---|---|
| Disponibilidade mensal | 99,9% | **99,5%** |
| Latência (p95) | 500 ms | **1.000 ms** |
| Janela de medição | 7 dias móveis (painel) / 30 dias (relatório) | Mês-calendário |
| Consequência | Congelamento de features | Crédito de serviço + relatório de causa raiz |

**Créditos de serviço** (aplicáveis a ONGs com contrato de plano pago):

| Disponibilidade no mês | Crédito |
|---|---|
| < 99,5% e ≥ 99,0% | 10% da mensalidade |
| < 99,0% e ≥ 95,0% | 25% da mensalidade |
| < 95,0% | 50% da mensalidade |

**Exclusões do SLA:** manutenção programada anunciada com 72 h de antecedência,
falha comprovada de provedor externo de pagamento, e uso acima do limite de
50 rps por origem definido no ingress.

---

## 4. Error Budget

Com SLO de 99,9% em 30 dias, o orçamento de indisponibilidade é:

| Janela | Tempo de "erro" permitido |
|---|---|
| 30 dias | **43 min 12 s** |
| 7 dias | **10 min 05 s** |
| 24 horas | **1 min 26 s** |

Métrica de budget restante (materializada como recording rule):

```promql
solidarytech:donation:error_budget_remaining_7d =
  1 - (
    sum(increase(http_requests_total{service="donation-service",http_response_status_code=~"5.."}[7d]))
    /
    (sum(increase(http_requests_total{service="donation-service"}[7d])) * 0.001)
  )
```

`1,0` = budget intacto · `0,0` = budget esgotado · negativo = SLO violado.

### 4.1 Política de error budget

| Budget restante | Postura da equipe |
|---|---|
| > 50% | Operação normal. Deploys de feature liberados. |
| 25% – 50% | Revisão obrigatória de confiabilidade em cada PR; deploys só em horário comercial. |
| 0% – 25% | Metade da capacidade do time vai para confiabilidade. Sem deploy sexta-feira. |
| ≤ 0% | **Congelamento de features.** Só entram correções de confiabilidade até o budget voltar a 25%. Alerta `DonationErrorBudgetExhausted` dispara automaticamente. |

Esta é a função real do error budget: transformar "estabilidade vs. velocidade"
de uma discussão de opinião em uma **regra combinada antes do incidente**.

---

## 5. Alertas por taxa de queima (burn rate)

Alertar quando "a taxa de erro passou de X%" gera ruído: um pico de 30 segundos
dispara o pager sem ameaçar o SLO. A abordagem adotada (SRE Workbook) alerta
sobre a **velocidade de consumo do error budget**, com janelas múltiplas.

**Fator de queima** = taxa de erro observada ÷ 0,1% permitido.

| Alerta | Condição | Consome | Severidade | Destino |
|---|---|---|---|---|
| `DonationErrorBudgetFastBurn` | queima > 14,4x nas janelas de **5m e 1h** | 2% do budget mensal em 1 h | `critical` | PagerDuty (acorda o plantão) + **self-healing automático** |
| `DonationErrorBudgetSlowBurn` | queima > 6x nas janelas de **30m e 6h** | 10% do budget em 6 h | `warning` | Ticket, sem acordar ninguém |
| `DonationErrorBudgetExhausted` | budget restante ≤ 0 em 7 dias | — | `critical` | Aciona a política de congelamento |
| `DonationLatencySLOBreach` | p95 > 500 ms por 5 min | — | `warning` | Ticket |

O uso de **duas janelas simultâneas** é intencional: a janela longa evita o
falso positivo de um pico isolado; a janela curta faz o alerta **resolver
rápido** quando o problema é corrigido — sem ela, o incidente ficaria aberto
por horas depois da correção.

Implementação: `gitops/base/observability/05-prometheus-rules.yaml`.

---

## 6. Dashboard SRE

`gitops/base/observability/07-grafana-dashboard-sre-slo.yaml` — importado
automaticamente pelo sidecar do Grafana (label `grafana_dashboard: "1"`).
Título no Grafana: **"SolidaryTech — SRE: SLO & Error Budget"**.

| Linha | Painéis |
|---|---|
| 🎯 SLO | Disponibilidade 7d (SLI) · **Error Budget restante (gauge)** · p95 · % < 500 ms · alertas de SLO ativos |
| 🔥 Burn rate | Fator de queima nas janelas 5m/1h/6h com linhas de corte em 6x e 14,4x · taxa de erro vs. limite de 0,1% |
| ⏱️ Golden Metrics | Latência p50/p95/p99 · RPS por status (empilhado) · saturação de CPU/memória sobre o limit |
| 🚑 MTTR | Réplicas prontas vs. desejadas (mostra HPA e self-healing agindo) · logs do self-healing-webhook vindos do Loki |

> **Observação de ambiente:** o Prometheus do laboratório usa `emptyDir` com
> retenção de 7 dias. Por isso o painel calcula o error budget em janela de
> 7 dias, enquanto o SLA contratual usa mês-calendário. Em conta própria,
> basta aumentar `retention` no `01-kube-prometheus-stack.yaml` e trocar `7d`
> por `30d` nas recording rules.

---

## 7. MTTR — como a stack reduz o tempo de recuperação

MTTR = **detectar + diagnosticar + corrigir + confirmar**. Cada etapa tem um
mecanismo específico:

| Etapa | Antes (voo cego) | Com a stack | Ganho |
|---|---|---|---|
| **Detectar** | Reclamação da ONG por e-mail | Regra de burn rate avalia a cada 30 s; `group_wait` de 10 s para críticos | de horas para **< 2 min** |
| **Notificar** | Alguém precisa perceber | PagerDuty aciona o plantão + Discord `#incidentes` | segundos |
| **Diagnosticar** | Login em pods, `grep` em log | Trace no Datadog mostra o span lento; log correlacionado por `trace_id` no Loki; painel SRE mostra se é erro, latência ou saturação | de dezenas de minutos para **< 5 min** |
| **Corrigir** | Humano roda `kubectl rollout restart` | `auto_heal="true"` → webhook reinicia o deployment sozinho (rate-limitado a 1 restart / 5 min) | de ~15 min para **~30 s** |
| **Confirmar** | Testar na mão | Janela curta do alerta resolve sozinha; `send_resolved` fecha o incidente no PagerDuty e avisa no Discord | automático |

**MTTR estimado para a falha mais comum** (pod degradado respondendo 5xx):
detecção 2 min + ação automática 30 s + confirmação 2 min ≈ **< 5 minutos**,
sem intervenção humana. O humano é acionado em paralelo e assume apenas se o
self-healing não resolver — o `repeat_interval` de 1 h garante que o incidente
volte a chamar se persistir.

**Anti-fadiga de alerta** (também é redução de MTTR: alerta demais é alerta
ignorado):
- `group_by: [alertname, namespace, service]` — 8 réplicas falhando = 1 incidente.
- `inhibit_rules` — crítico aberto silencia os warnings do mesmo namespace.
- Warnings nunca acordam ninguém; viram ticket.
- Rate limit no self-healing evita loop de restart mascarando o problema real.
