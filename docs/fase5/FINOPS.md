# FinOps — Tagueamento, Rightsizing e Forecast

> "O orçamento da ONG é limitado, cada centavo conta." Este documento mostra
> **onde o dinheiro está**, **como cada centavo é atribuído a um dono** e
> **o que já foi feito e o que ainda pode ser feito** para gastar menos.

---

## 1. Política de tagueamento (implementada em IaC)

### 1.1 Tags obrigatórias

| Tag | Valor | Para que serve |
|---|---|---|
| `Project` | `SolidaryTech` | Separa a plataforma de qualquer outra carga na conta |
| `Environment` | `Production` | Distingue produção de ambientes efêmeros |
| `CostCenter` | `NGO-Core` | Rateio contábil: é este campo que a diretoria vê no relatório |
| `Owner` | `plataforma@solidarytech.org` | Quem é acionado quando um recurso aparece caro ou órfão |
| `ManagedBy` | `terraform` | Recurso sem esta tag = criado à mão = candidato a deleção |
| `Phase` | `fase5-hackathon` | Rastreabilidade acadêmica |
| `Criticality` | `high` | Prioriza o que não pode ser desligado em corte de custo |
| `DR` | `primary` / `standby` | Separa o custo do ambiente ativo do custo do espelho |

### 1.2 Aplicação em duas camadas (defesa em profundidade)

**Camada 1 — `default_tags` no provider** (`terraform/providers.tf`): qualquer
recurso criado por qualquer módulo herda as tags, mesmo que o autor do módulo
esqueça.

```hcl
provider "aws" {
  region = var.aws_region
  default_tags { tags = local.common_tags }
}
```

**Camada 2 — `merge()` explícito nos módulos**: cada recurso ainda recebe
`tags = merge(var.tags, { Name = ..., Service = ... })`, o que torna a
intenção auditável no `terraform plan`.

> **Por que duas camadas?** `default_tags` sozinho é invisível no código do
> módulo (fácil de alguém assumir que "não tem tag"); `merge()` sozinho falha
> quando alguém esquece. Juntos, não há recurso sem tag.

### 1.3 Como evidenciar (comandos para o vídeo/relatório)

```bash
# 1) Todos os recursos com a tag Project=SolidaryTech
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=Project,Values=SolidaryTech \
  --query 'ResourceTagMappingList[].ResourceARN' --output table

# 2) Recursos SEM a tag obrigatória (deve retornar vazio)
aws resourcegroupstaggingapi get-resources \
  --query "ResourceTagMappingList[?!not_null(Tags[?Key=='CostCenter'])].ResourceARN"

# 3) Custo por CostCenter no Cost Explorer
aws ce get-cost-and-usage \
  --time-period Start=$(date -d '30 days ago' +%F),End=$(date +%F) \
  --granularity MONTHLY --metrics UnblendedCost \
  --group-by Type=TAG,Key=CostCenter
```

No console: **Billing → Cost Explorer → Group by → Tag → `CostCenter`**.
(É necessário ativar `Project`, `CostCenter` e `Owner` como *cost allocation
tags* em Billing → Cost allocation tags; leva até 24 h para popular.)

---

## 2. Guardrails financeiros automatizados

`terraform/modules/finops/` cria dois controles complementares:

### 2.1 AWS Budgets — teto com alerta preditivo

| Gatilho | Tipo | O que significa |
|---|---|---|
| 80% de US$ 400 | `ACTUAL` | Consumo real passou de US$ 320 — ainda dá tempo de agir |
| 100% de US$ 400 | `ACTUAL` | Estourou o mês |
| 100% de US$ 400 | **`FORECASTED`** | A AWS projeta estouro no fim do mês — **este é o alerta que evita a surpresa** |

O budget é filtrado por `user:Project$SolidaryTech`, o que só funciona porque
a política de tagueamento cobre 100% dos recursos.

### 2.2 Cost Anomaly Detection — desvio estatístico

Um monitor dimensional por serviço AWS com assinatura diária. Só notifica
anomalias com impacto absoluto **≥ US$ 20**, evitando fadiga de alerta
financeiro. Ele pega o que o Budget não pega: um pico de US$ 30/dia em um
serviço específico enquanto o mês, no total, ainda está dentro do teto.

---

## 3. Rightsizing

### 3.1 Método

1. Medir o consumo real (painel *"FinOps — rightsizing: uso real vs. request
   declarado"*, no dashboard de visão geral).
2. Definir `requests` = baseline observado + folga de ~2x (o `request` é o que
   o scheduler reserva — inflá-lo desperdiça o cluster inteiro).
3. Definir `limits` ≈ 2x a 3x o pico observado (o `limit` protege o vizinho,
   não deve estrangular o pico legítimo).
4. Deixar o HPA absorver crescimento horizontal em vez de superdimensionar
   verticalmente.
5. Revisar quando `HighCpuUsage`/`HighMemoryUsage` dispararem (subdimensionado)
   ou quando o painel mostrar uso cronicamente abaixo do request (desperdício).

### 3.2 Valores aplicados (via GitOps)

| Serviço | Baseline medido | `requests` | `limits` | HPA | Justificativa |
|---|---|---|---|---|---|
| `ngo-service` | ~40m / ~90Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% | Cadastro, tráfego baixo e previsível |
| `donation-service` | ~60m / ~110Mi (pico 280m) | 150m / 192Mi | 500m / 384Mi | **2–8 @65%** | Hot Path: mínimo 2 réplicas por HA, escala antes da latência subir |
| `volunteer-service` | ~35m / ~85Mi | 100m / 128Mi | 300m / 256Mi | 1–4 @70% | Gargalo é o `Scan` no DynamoDB, não a CPU do pod |
| `self-healing-webhook` | ~10m / ~40Mi | 50m / 64Mi | 200m / 128Mi | — | Executa 1 ação a cada vários minutos |

Componentes de plataforma também foram dimensionados: Prometheus
(50m/256Mi → 500m/768Mi), Loki (50m/128Mi → 500m/384Mi), OTel Collector
(50m/128Mi → 400m/384Mi), ArgoCD controller (250m/512Mi → 1000m/1024Mi),
Velero (50m/128Mi → 300m/384Mi).

**Soma dos requests dos 3 serviços em regime normal:** 350m CPU / 448Mi —
cabe folgado em 1 node `t3.medium` (2 vCPU / 4 GiB), sobrando capacidade para
a stack de observabilidade nos outros 2 nodes.

### 3.3 Node group

De 4 para **3 × t3.medium** (`desired=3`, `min=2`, `max=5`): a Fase 4 tinha 5
microsserviços, a Fase 5 tem 3. Economia direta de **US$ 30,37/mês**.

---

## 4. Forecast de custos

> Preços de referência **us-east-1, On-Demand, agosto/2026**, 730 h/mês.
> O preço do control plane do EKS (US$ 0,10/cluster/hora) foi verificado na
> página oficial de pricing. Os demais seguem a tabela pública da AWS e devem
> ser reconferidos no AWS Pricing Calculator na data da entrega.

### 4.1 Cenário BASE — operação normal

| Componente | Dimensionamento | Cálculo | US$/mês |
|---|---|---|---:|
| EKS — control plane | 1 cluster | 0,10 × 730 | **73,00** |
| EC2 — worker nodes | 3 × t3.medium | 3 × 0,0416 × 730 | **91,10** |
| EBS — discos dos nodes | 3 × 20 GB gp3 | 60 × 0,08 | 4,80 |
| RDS — PostgreSQL | 2 × db.t3.micro | 2 × 0,018 × 730 | **26,28** |
| RDS — armazenamento | 2 × 20 GB gp3 | 40 × 0,115 | 4,60 |
| RDS — backups (7 dias) | dentro da franquia | — | 0,00 |
| NAT Gateway — horas | 1 | 0,045 × 730 | **32,85** |
| NAT Gateway — dados | ~60 GB | 60 × 0,045 | 2,70 |
| NLB (ingress) — horas | 1 | 0,0225 × 730 | **16,43** |
| NLB — LCU | uso baixo | estimado | 4,50 |
| DynamoDB | on-demand + 1 GB + PITR | estimado | 1,95 |
| SQS | ~2 M req (1 M grátis) | 1 × 0,40 | 0,40 |
| ECR | ~8 GB | 8 × 0,10 | 0,80 |
| S3 — backups Velero (DR) | ~10 GB + requests | — | 0,53 |
| Secrets Manager | 2 segredos | 2 × 0,40 | 0,80 |
| Transferência de dados | ~50 GB saída | estimado | 2,00 |
| CloudWatch | logs mínimos | estimado | 0,50 |
| **TOTAL AWS** | | | **≈ US$ 263,24** |

**Ferramentas SaaS:** Datadog (plano *For Education*) US$ 0 · PagerDuty
(*Developer*) US$ 0 · Discord US$ 0 · GitHub Actions (repo público) US$ 0.

**Projeção anual:** US$ 263,24 × 12 ≈ **US$ 3.158,88/ano**.

### 4.2 Cenário PICO — 7 dias de exposição em rede nacional

O HPA leva o `donation-service` de 2 para 6–8 réplicas e o node group de 3
para 5 nodes durante a semana de pico.

| Delta | US$ |
|---|---:|
| +2 nodes t3.medium por 7 dias | +13,98 |
| +EBS dos nodes extras | +0,75 |
| +Tráfego no NAT e no NLB | +4,80 |
| +DynamoDB / SQS / transferência | +3,00 |
| **Total do mês com pico** | **≈ US$ 285,77** |

O teto de US$ 400 absorve o pico sem disparar o alerta de 100% — mas o alerta
`FORECASTED` avisa se o pico se prolongar.

### 4.3 Cenário DESASTRE — failover ativo por 3 dias

| Delta | US$ |
|---|---:|
| Cluster espelho completo (EKS + 3 nodes + 2 RDS + NAT + NLB) por 3 dias | +24,00 |
| Restore e transferência entre regiões | +6,00 |
| **Impacto pontual** | **≈ US$ 30,00** |

Custo de manter o espelho **desligado**: **US$ 0** — o bucket de backup
(US$ 0,53/mês) é a única despesa recorrente do DR.

---

## 5. Recomendações de otimização

### 5.1 Recomendação principal — Compute Savings Plans

**Ação:** contratar um *Compute Savings Plan* de **1 ano, sem pagamento
adiantado**, cobrindo a base fixa de 3 nodes.

| | Valor |
|---|---:|
| Custo On-Demand dos nodes | US$ 91,10/mês |
| Desconto típico (1 ano, no upfront) | ~28% |
| **Economia** | **≈ US$ 25,51/mês — US$ 306,12/ano** |

**Por que é a recomendação nº 1:** os worker nodes são o segundo maior item da
fatura e são carga **permanente e previsível** (o cluster nunca é desligado).
Savings Plan não exige mudança de código, arquitetura ou tipo de instância — o
desconto se aplica automaticamente, e o excedente do pico continua sendo
cobrado On-Demand normalmente. Risco: compromisso de 1 ano; mitigado por
contratar apenas a base (3 nodes) e nunca o pico.

### 5.2 Demais recomendações, por retorno

| # | Ação | Economia estimada | Esforço |
|---|---|---:|---|
| 2 | Migrar nodes para **Graviton** (`t4g.medium`, US$ 0,0336/h). Ambas as imagens são multiplataforma (Go compila para arm64; wheels Python existem) | US$ 17,52/mês | Médio (rebuild multi-arch) |
| 3 | **VPC Gateway Endpoints** para S3 e DynamoDB (custo zero) — tira esse tráfego do NAT | US$ 1,50–2,70/mês (cresce com escala) | Baixo |
| 4 | ✅ **Já feito:** ElastiCache não provisionado (nenhum serviço usa cache) | US$ 12,41/mês evitados | — |
| 5 | ✅ **Já feito:** node group de 4 → 3 nodes | US$ 30,37/mês | — |
| 6 | ✅ **Já feito:** lifecycle policy no ECR (10 imagens tageadas, untagged expira em 1 dia) | evita crescimento indefinido | — |
| 7 | ✅ **Já feito:** lifecycle no bucket do Velero (STANDARD_IA em 30 d, expira em 90 d) | ~50% do storage de backup | — |
| 8 | ✅ **Já feito:** DR destruído em repouso (Warm Standby sob demanda) | evita duplicar ~US$ 240/mês | — |
| 9 | Criar **GSI `ngo_id`** no DynamoDB e trocar `Scan` por `Query` no `volunteer-service` — o `Scan` lê a tabela inteira a cada consulta | cresce linearmente com a base | Médio (código + IaC) |
| 10 | Avaliar substituir o NAT Gateway por endpoints + saída controlada, se o tráfego de saída permanecer baixo | até US$ 32,85/mês | Alto |

**Se as ações 1 + 2 + 3 forem executadas:** US$ 263,24 → **≈ US$ 218/mês**
(−17%), sem perder nenhuma capacidade.

---

## 6. Ritual de FinOps

| Frequência | Ritual | Responsável |
|---|---|---|
| Diário (automático) | Cost Anomaly Detection avalia desvios e envia e-mail | Automático |
| Semanal | Revisar o painel *uso real vs. request* e ajustar quem estiver fora da faixa | Squad de plataforma |
| Mensal | Fechar custo por `CostCenter` no Cost Explorer e comparar com o forecast | Squad + diretoria |
| Trimestral | Reavaliar Savings Plan, tipos de instância e recursos órfãos (sem tag `ManagedBy=terraform`) | Squad de plataforma |

---

**Fontes de preço:**
[Amazon EKS Pricing](https://aws.amazon.com/eks/pricing/) ·
[Amazon VPC FAQs (NAT Gateway)](https://aws.amazon.com/vpc/faqs/) ·
[Cost optimization for Kubernetes on AWS](https://aws.amazon.com/blogs/containers/cost-optimization-for-kubernetes-on-aws/)
