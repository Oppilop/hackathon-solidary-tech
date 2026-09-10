# Roteiro do Vídeo — 20 minutos

> O edital cobra **pitch executivo (15–20 min)** *e* **demo técnica**. Um vídeo
> de 20 min não comporta os dois separados: a estrutura abaixo intercala —
> cada bloco abre com a fala executiva ("por que a diretoria deveria pagar por
> isso") e fecha com a evidência técnica na tela.
>
> **Regra de ouro do edital:** *"Não basta configurar; é preciso mostrar
> operando na prática."* Toda afirmação deste roteiro tem uma tela associada.

---

## Preparação (fazer ANTES de gravar)

- [ ] Ambiente no ar há pelo menos **1 hora** (SLO e error budget precisam de série histórica)
- [ ] Laço de `curl` rodando há ~15 min (Etapa 6 do guia de execução)
- [ ] Abas abertas e logadas: ArgoCD · Grafana (2 dashboards) · Datadog (Service Map, um trace, Watchdog) · PagerDuty · Discord · GitHub Actions · AWS Console (Cost Explorer, Tag Editor, S3 do Velero)
- [ ] Terminal com fonte grande, `kubectl` e `velero` configurados
- [ ] Um pipeline recém-executado com **verde** e um com o **Trivy bloqueando** (pode ser um run anterior)
- [ ] Cronômetro à vista

---

## Bloco 0 — Abertura (0:00 – 1:00)

**Tela:** slide único com nome do grupo, RMs e o diagrama de arquitetura.

> "Somos [nomes / RMs]. A SolidaryTech conecta ONGs, doadores e voluntários.
> Depois de aparecer em rede nacional, a plataforma passou a ter picos
> imprevisíveis — e a diretoria fez três perguntas: *se a nuvem cair, as
> doações param?* *quanto isso custa e por quê?* *descobrimos o problema antes
> ou depois do doador?* Nos próximos 20 minutos respondemos as três, mostrando
> tudo funcionando."

---

## Bloco 1 — Fundação DevOps (1:00 – 6:00) · 5 min

### 1.1 IaC — Terraform (1:00 – 2:30)

**Fala:** "Nada foi clicado no console. Todo o ambiente — rede, EKS, dois
PostgreSQL, DynamoDB, SQS, ECR — nasce de código versionado, com revisão em
pull request."

**Tela:**
- `terraform/main.tf` e a pasta `modules/` (rolar rápido)
- **Actions → Terraform Infra**: abrir um run e mostrar `plan` e `apply` verdes
- `terraform/providers.tf`: destacar o bloco `default_tags` — *"guarde essa
  tela, ela volta no bloco de FinOps"*

### 1.2 CI/CD DevSecOps (2:30 – 4:00)

**Fala:** "Toda mudança de código passa por uma esteira que **bloqueia** o
deploy se encontrar vulnerabilidade crítica."

**Tela:**
- `Actions → CI/CD Microservices`: os 5 jobs em paralelo
- Abrir `donation-service` → job **Security Scan**: log do Trivy e do `gosec`
- Mostrar um run em que o Trivy falhou com CRITICAL — *"o merge foi bloqueado"*
- Job **Update GitOps Manifest**: o commit automático com a nova tag

### 1.3 GitOps — ArgoCD (4:00 – 5:00)

**Fala:** "O commit anterior é o único gatilho de deploy. Não existe `kubectl
apply` de aplicação neste projeto."

**Tela:**
- UI do ArgoCD com todas as Applications `Synced / Healthy`
- Entrar em `donation` → árvore de recursos

### 1.4 Observabilidade (5:00 – 6:00)

**Fala:** "Os três sinais saem dos serviços por OpenTelemetry, passam por um
Collector único e vão para Prometheus, Loki e Datadog."

**Tela:**
- Datadog → **Service Map**: os 3 serviços e as dependências (RDS, SQS, DynamoDB)
- Abrir **um trace** de `POST /donations`: span HTTP → span do banco → **span do SQS**
  → *"o traceparent viaja dentro da mensagem: o trace não morre na fila"*

---

## Bloco 2 — SRE: confiabilidade com contrato (6:00 – 10:00) · 4 min

### 2.1 O acordo (6:00 – 7:00)

**Fala executiva:** "Confiabilidade sem número é opinião. O `donation-service`
é o Hot Path: dois SLIs — disponibilidade e latência. SLO interno de **99,9%**
e p95 abaixo de **500 ms**; SLA com as ONGs de **99,5%**. A diferença entre
99,9% e 99,5% é a nossa margem para corrigir antes de descumprir contrato.
Em 30 dias, o orçamento de erro é de **43 minutos**."

**Tela:** tabela de SLI/SLO/SLA em [SRE-SLO-SLI-SLA.md](SRE-SLO-SLI-SLA.md).

### 2.2 Dashboard SRE ao vivo (7:00 – 9:00)

**Tela:** Grafana → **"SolidaryTech — SRE: SLO & Error Budget"**

Percorrer, nesta ordem:
1. **Disponibilidade 7d** e o **gauge de Error Budget restante** — *"esta é a tela que a diretoria olha"*
2. **Fator de queima** com as linhas de corte em 6x e 14,4x
3. **Golden Metrics**: latência p50/p95/p99, RPS por status, saturação vs. limits
4. Prometheus → `Alerts`: mostrar as regras `DonationErrorBudgetFastBurn` e
   `SlowBurn` carregadas

**Fala:** "Não alertamos por 'taxa de erro passou de X'. Alertamos pela
**velocidade de consumo do orçamento**, com duas janelas ao mesmo tempo —
a longa evita falso positivo, a curta faz o alerta fechar assim que o problema
some."

### 2.3 MTTR na prática (9:00 – 10:00)

**Tela:** terminal, executar ao vivo:

```bash
kubectl -n donation-namespace set env deployment/donation-service DATABASE_URL="postgres://errado"
```

Mostrar, em sequência: alerta disparando no Prometheus → incidente no
PagerDuty → mensagem no **Discord** → log do `self-healing-webhook` → pod
reiniciando → alerta resolvendo.

**Fala:** "Detecção em menos de 2 minutos, correção automática em cerca de 30
segundos. O humano é chamado em paralelo e só assume se a automação não
resolver. É assim que o MTTR cai de dezenas de minutos para menos de cinco."

---

## Bloco 3 — FinOps: cada centavo com dono (10:00 – 14:00) · 4 min

### 3.1 Tagueamento (10:00 – 11:15)

**Fala:** "Não dá para otimizar o que não se consegue atribuir. Toda a política
de tags está no Terraform, em duas camadas: `default_tags` no provider pega
tudo, e o `merge()` explícito em cada módulo torna a intenção auditável."

**Tela:**
- `terraform/main.tf` → bloco `local.common_tags`
- Console AWS → **Tag Editor**: filtrar `Project = SolidaryTech` e mostrar a lista
- Console AWS → **Cost Explorer → Group by → Tag → CostCenter**

### 3.2 Rightsizing (11:15 – 12:30)

**Fala:** "Requests não foram chutados: foram medidos."

**Tela:**
- Grafana → dashboard de visão geral → linha **"FinOps — uso real vs. request"**
- `gitops/base/donation/deployment.yaml`: bloco `resources` com o comentário
  do baseline medido
- HPA do Hot Path: `minReplicas: 2`, `maxReplicas: 8`, alvo de 65%

**Fala:** "Node group de 4 para 3 nodes — 30 dólares por mês. ElastiCache não
provisionado, porque nenhum serviço usa cache — mais 12 dólares que a ONG não
paga por recurso ocioso."

### 3.3 Forecast e guardrails (12:30 – 14:00)

**Tela:** tabela de forecast em [FINOPS.md](FINOPS.md).

**Fala executiva:** "A plataforma custa **cerca de 263 dólares por mês** —
cerca de 3.160 por ano. O maior item é o control plane do EKS, seguido dos
worker nodes. Numa semana de pico de mídia, chega a 286: o teto de 400 absorve
sem sustos. Nossa recomendação principal é um **Compute Savings Plan de 1 ano
sem entrada** para a base fixa de três nodes: **25 dólares por mês, 306 por
ano**, sem mudar uma linha de código. Migrar para Graviton adiciona mais 17
por mês."

**Tela:** Console AWS → **Budgets** (os 3 alertas, incluindo o `FORECASTED`) e
**Cost Anomaly Detection**.

---

## Bloco 4 — ITSM e AIOps (14:00 – 16:00) · 2 min

**Fala:** "Regra só pega o que alguém previu. Por isso o Watchdog do Datadog
aprende o comportamento normal de cada serviço e sinaliza desvio sem limiar
configurado."

**Tela:**
- Datadog → **Watchdog → Insights**
- Diagrama do ciclo de vida do incidente em [ITSM-AIOPS.md](ITSM-AIOPS.md)
- PagerDuty: o incidente do Bloco 2 já resolvido, com a linha do tempo
- Discord `#incidentes`: alerta e resolução

**Fala:** "Detecção → triagem no Alertmanager, que agrupa e inibe para não
gerar oito incidentes de um problema só → resposta automática **em paralelo**
com a notificação humana → diagnóstico por trace e log correlacionados →
correção sempre por commit → post-mortem sem culpados, obrigatório para todo
P1 e sempre que 20% do error budget for consumido."

---

## Bloco 5 — Continuidade e DR (16:00 – 19:00) · 3 min

### 5.1 O compromisso (16:00 – 16:45)

**Fala executiva:** "Se a região da AWS cair, a SolidaryTech volta a aceitar
doações em **até 4 horas**, perdendo no máximo **5 minutos** de transações.
Esses são o RTO e o RPO que assinamos — e temos dois mecanismos, porque eles
protegem coisas diferentes: um protege o **estado**, o outro protege a
**capacidade de executar**."

**Tela:** tabela de RTO/RPO em [PCN-DR.md](PCN-DR.md).

### 5.2 Opção A — Velero (16:45 – 18:00)

**Tela:**
```bash
velero schedule get      # diário completo + horário do donation-namespace
velero backup get
velero backup describe <mais-recente> --details
aws s3 ls s3://<bucket>/backups/ --region us-west-2
```
**Fala:** "O bucket está em **us-west-2**, região diferente da primária, de
propósito. Versionado e criptografado."

Demonstrar o restore: apagar um ConfigMap e trazê-lo de volta com
`velero restore create`.

### 5.3 Opção B — Warm Standby (18:00 – 19:00)

**Tela:** `terraform/dr/main.tf` — mostrar que ele chama `../modules/...`

**Fala:** "Nenhum código duplicado: é o mesmo módulo do primário, com outra
região e outro state. E aponta para o **mesmo repositório GitOps** — não
existem manifestos paralelos que possam divergir."

**Tela:** `Actions → Terraform DR (Warm Standby) → Run workflow` → mostrar o
`plan` (ou o `apply` já executado, com o `failover_checklist` no output).

**Fala:** "Um acionamento levanta a região secundária inteira. Em repouso ela
fica destruída: custo zero. O único gasto recorrente do DR é o bucket de
backup — cinquenta centavos por mês."

---

## Bloco 6 — Fechamento (19:00 – 20:00) · 1 min

**Tela:** slide de resumo.

> "Fechando as três perguntas da diretoria:
> **Se a nuvem cair, as doações param?** Não — 4 horas de RTO, 5 minutos de RPO,
> com backup cross-region e ambiente espelho que sobe com um comando.
> **Quanto custa e por quê?** 263 dólares por mês, cada centavo atribuído a um
> CostCenter, com teto, alerta preditivo e uma recomendação que economiza 306
> dólares por ano.
> **Descobrimos antes do doador?** Sim — o error budget avisa pela velocidade
> de queima, o Watchdog pega o que ninguém previu, e a primeira correção
> acontece em 30 segundos, sem esperar um humano acordar.
> Tudo o que mostramos está versionado no repositório. Obrigado."

---

## Checklist final antes de enviar

- [ ] Duração ≤ 20 min
- [ ] Áudio limpo e telas legíveis (fonte grande no terminal)
- [ ] **Nenhuma credencial visível** (token do AWS Academy, chave do Datadog, webhook do Discord)
- [ ] Todos os 5 requisitos aparecem **operando**, não apenas configurados
- [ ] Vídeo não listado no YouTube (ou Drive com link público) e link no relatório
