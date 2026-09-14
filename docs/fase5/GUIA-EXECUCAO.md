# Guia de Execução — do zero ao ambiente no ar

> Ordem importa. Cada etapa só funciona se a anterior estiver concluída.

---

## Etapa 0 — Pré-requisitos

| Item | Onde obter |
|---|---|
| Conta AWS Academy com `LabRole` | Laboratório da POSTECH |
| Repositório GitHub (público ou com Actions habilitado) | — |
| Conta Datadog (plano *For Education*) | https://www.datadoghq.com/ |
| Conta PagerDuty (plano *Developer*) | https://www.pagerduty.com/ |
| Webhook do Discord no canal de incidentes | Configurações do servidor → Integrações |
| Local: `aws` CLI, `kubectl`, `terraform` ≥ 1.10, `git` | — |

---

## Etapa 1 — Secrets do repositório

`Settings → Secrets and variables → Actions → New repository secret`

| Secret | Valor | Obrigatório |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Do painel "AWS Details" do laboratório | ✅ |
| `AWS_SECRET_ACCESS_KEY` | idem | ✅ |
| `AWS_SESSION_TOKEN` | idem (expira em ~4 h — **reatualizar a cada sessão**) | ✅ |
| `TF_STATE_BUCKET` | Nome global único, ex.: `solidarytech-tfstate-<seu-rm>` | ✅ |
| `GITOPS_TOKEN` | PAT com escopo `repo` (para o CI commitar o bump da imagem) | Recomendado |
| `DD_API_KEY` | Datadog → Organization Settings → API Keys | ✅ |
| `DD_SITE` | Região da conta, **sem** `https://`. US1 = `datadoghq.com` (sem prefixo!), US3/US5 = `us3...`/`us5.datadoghq.com`, EU = `datadoghq.eu`. Confira na URL do seu Datadog — errar a região faz o agente descartar a telemetria **em silêncio**. | ✅ |
| `PAGERDUTY_INTEGRATION_KEY` | Serviço no PagerDuty → Integrations → Events API V2 | ✅ |
| `DISCORD_WEBHOOK_URL` | URL do webhook **+ sufixo `/slack`** | ✅ |

> ⚠️ **O token do AWS Academy expira.** Se um workflow falhar com
> `ExpiredToken` ou `InvalidClientTokenId`, atualize os três secrets da AWS e
> rode de novo.

---

## Etapa 2 — Ajustar valores do projeto

1. **Bucket do Velero** (nome S3 é global). Trocar nos **dois** lugares:
   - `terraform/terraform.tfvars` → `velero_bucket_name`
   - `gitops/base/observability/08-velero.yaml` → `configuration.backupStorageLocation[0].bucket`
2. **E-mail de FinOps**: `terraform/variables.tf` →
   `budget_notification_email` (recebe alertas de orçamento e anomalia).
3. **Links de runbook**: substituir `SEU-USUARIO` em
   `gitops/base/observability/05-prometheus-rules.yaml`.

---

## Etapa 3 — Provisionar a infraestrutura

**Pelo pipeline (recomendado):**

`Actions → Terraform Infra → Run workflow → action: apply`

O workflow: cria o bucket de state se não existir → `fmt/init/validate/plan`
→ `apply` → cria os Secrets do Datadog e do Alertmanager → espera o ArgoCD →
imprime a URL do NLB.

**Localmente (alternativa):**

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # preencher credenciais
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=solidarytech/fase5/terraform.tfstate" \
  -backend-config="region=us-east-1" -backend-config="encrypt=true"
terraform apply
```

⏱️ 15–25 min (EKS e RDS são os demorados).

> Se o apply falhar em `aws_budgets_budget` ou `aws_ce_anomaly_monitor` com
> `AccessDenied`, o laboratório bloqueia essas APIs: defina
> `enable_cost_guardrails = false` e evidencie os guardrails pelo console
> (ver [FINOPS.md](FINOPS.md)).

---

## Etapa 4 — Acessar o cluster

```bash
aws eks update-kubeconfig --region us-east-1 --name togglemaster-eks-prod

# ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d ; echo
kubectl -n argocd port-forward svc/argocd-server 8080:80
# http://localhost:8080  (usuário: admin)
```

---

## Etapa 5 — Publicar as imagens

`Actions → CI/CD Microservices → Run workflow → force_all: true`

Cada serviço roda build → lint → SAST/SCA → Docker + Trivy → push no ECR →
commit que atualiza a tag no manifesto. Esse commit é o gatilho do ArgoCD.

⏱️ 8–12 min. Antes disso os pods ficam em `ImagePullBackOff` — é esperado, a
imagem ainda não existe.

---

## Etapa 6 — Verificar a entrega

```bash
kubectl get applications -n argocd -o wide     # tudo Synced/Healthy
kubectl get pods -A | grep -E "ngo|donation|volunteer|observability|velero"

NLB=$(kubectl -n ingress-nginx get svc ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl http://$NLB/api/ngo/health
curl http://$NLB/api/donation/health
curl http://$NLB/api/volunteer/health
```

**Gerar dados reais** (necessário para os painéis de SLO saírem do zero):

```bash
curl -X POST http://$NLB/api/ngo/ngos -H 'Content-Type: application/json' \
  -d '{"name":"Mãos Solidárias","email":"contato@maos.org","cause":"Fome","city":"Recife"}'

curl -X POST http://$NLB/api/donation/donations -H 'Content-Type: application/json' \
  -d '{"ngo_id":1,"amount":150.00,"donor_name":"Vitor"}'

curl -X POST http://$NLB/api/volunteer/volunteers -H 'Content-Type: application/json' \
  -d '{"name":"Ana","email":"ana@email.com","ngo_id":1}'

# Tráfego contínuo para o painel de SRE (deixar rodando ~10 min antes de gravar)
while true; do curl -s -o /dev/null http://$NLB/api/donation/donations; sleep 0.5; done
```

---

## Etapa 7 — Observabilidade

```bash
# Grafana (admin / postech2026)
kubectl -n observability port-forward svc/kps-grafana 3000:80

# Prometheus
kubectl -n observability port-forward svc/kps-kube-prometheus-stack-prometheus 9090:9090
```

Dashboards a abrir: **"SolidaryTech — SRE: SLO & Error Budget"** e
**"SolidaryTech — Visão Geral da Plataforma"**.

No Datadog: `APM → Service Map` (os 3 serviços e suas dependências), um trace
de `POST /donations` mostrando o span do SQS, e `Watchdog → Insights`
(ativação descrita em [ITSM-AIOPS.md](ITSM-AIOPS.md)).

---

## Etapa 8 — Validar o DR

```bash
# Velero
kubectl -n velero get pods
velero schedule get
velero backup create demo-hackathon --include-namespaces donation-namespace --wait
velero backup describe demo-hackathon --details
aws s3 ls s3://<seu-bucket-velero>/backups/ --region us-west-2

# Teste de restore
kubectl delete configmap donation-postgres-init-cm -n donation-namespace
velero restore create --from-backup demo-hackathon --include-resources configmaps
kubectl get configmap donation-postgres-init-cm -n donation-namespace   # voltou
```

**Warm Standby** — `Actions → Terraform DR (Warm Standby) → Run workflow`:
use `plan` para evidenciar sem gastar; `apply` para levantar de verdade;
`destroy` para desligar depois.

---

## Etapa 9 — Demonstrar o self-healing

```bash
# Forçar erro 5xx no donation-service quebrando a env do banco
kubectl -n donation-namespace set env deployment/donation-service DATABASE_URL="postgres://errado"

# Acompanhar: alerta → PagerDuty → Discord → restart automático
kubectl -n observability logs -l app=self-healing-webhook -f
kubectl -n donation-namespace get pods -w

# Restaurar (o ArgoCD também reverte sozinho pelo selfHeal)
kubectl -n argocd app actions run donation restart --kind Deployment 2>/dev/null || \
  kubectl -n donation-namespace rollout restart deployment/donation-service
```

---

## Etapa 10 — Encerrar (evitar custo)

```bash
# 1) DR primeiro, se estiver de pé
#    Actions → Terraform DR → action: destroy
# 2) Ambiente primário
#    Actions → Terraform Infra → action: destroy
```

O workflow de destroy limpa as Applications do ArgoCD e esvazia o bucket
versionado do Velero antes do `terraform destroy` — sem isso, o destroy falha.

---

## Solução de problemas

| Sintoma | Causa provável | Correção |
|---|---|---|
| `ExpiredToken` no Actions | Token do Academy expirou | Atualizar os 3 secrets da AWS |
| Pods em `ImagePullBackOff` | CI ainda não publicou a imagem | Rodar **CI/CD Microservices** com `force_all` |
| Application `OutOfSync` sem convergir | Falta o Secret criado fora do Git | Rodar de novo o job `post-apply-check` |
| Nada de trace no Datadog | `DD_SITE` com `https://` | O pipeline normaliza; se aplicou à mão, remover o protocolo |
| Painel de SLO vazio | Sem tráfego | Rodar o laço de `curl` da Etapa 6 por alguns minutos |
| `velero backup` em `PartiallyFailed` | Credencial do bucket ou região errada | Conferir `velero-credentials` e o nome do bucket nos dois arquivos |
| `terraform destroy` falha no bucket | Bucket versionado não vazio | O workflow já trata; à mão, apagar versões antes |
| Prometheus reiniciando (OOM) | Retenção alta demais para `t3.medium` | Reduzir `retention` em `01-kube-prometheus-stack.yaml` |
