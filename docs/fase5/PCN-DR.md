# Plano de Continuidade de Negócios (PCN) e Disaster Recovery

**Organização:** SolidaryTech
**Sistema:** Plataforma de doações e voluntariado
**Versão:** 1.0 — Fase 5 (Hackathon POSTECH DCLT)
**Aprovação:** Diretoria de Tecnologia · Revisão semestral obrigatória

---

## 1. Sumário executivo

A SolidaryTech intermedia doações para ONGs em todo o Brasil. Uma
indisponibilidade não gera apenas insatisfação: **doação não realizada é
doação perdida** — o doador raramente volta, e a ONG parceira deixa de receber
o recurso.

Este plano estabelece o que a plataforma promete em caso de desastre
(RTO/RPO), quais mecanismos sustentam essa promessa, e o passo a passo de
recuperação. Todos os mecanismos são **código versionado**, não procedimento
em documento.

**Compromisso central:** diante da perda total da região primária da AWS, a
plataforma volta a aceitar doações em **até 4 horas**, com perda máxima de
**5 minutos** de transações confirmadas.

---

## 2. Análise de impacto (BIA)

| Processo de negócio | Sistema | Criticidade | Impacto de 1 hora parada |
|---|---|---|---|
| Receber doação | `donation-service` + RDS `donationdb` + SQS | **Crítica** | Receita perdida e não recuperável; dano reputacional com as ONGs |
| Cadastrar/consultar ONG | `ngo-service` + RDS `ngodb` | Média | Onboarding de novas ONGs atrasa; doações a ONGs já cadastradas continuam |
| Inscrever voluntário | `volunteer-service` + DynamoDB | Baixa | Inscrição pode ser refeita depois, sem perda financeira |
| Observabilidade | Prometheus/Loki/Grafana/Datadog | Média | Operação segue, mas "às cegas" — aumenta o MTTR de qualquer outro incidente |
| CI/CD e GitOps | GitHub Actions + ArgoCD | Média | Impede correções durante o próprio desastre |

---

## 3. RTO e RPO acordados

| Componente | **RTO** | **RPO** | Mecanismo que sustenta |
|---|---|---|---|
| **Doações (dados)** | **4 h** | **5 min** | Backup automático do RDS + PITR nativo (retenção 7 dias) |
| **Doações (serviço)** | **4 h** | — | Warm Standby via `terraform/dr/` + restore Velero |
| Voluntários (DynamoDB) | 4 h | **5 min** | Point-in-Time Recovery habilitado (35 dias) |
| Cadastro de ONGs | 8 h | 24 h | Backup automático do RDS |
| Estado do cluster (manifestos) | 2 h | **1 h** | Velero: backup horário do `donation-namespace`, diário do restante |
| Configuração da infraestrutura | 1 h | 0 | Terraform versionado — o código **é** o backup |
| Configuração das aplicações | 15 min | 0 | GitOps — o repositório **é** o backup |

### Por que estes números

- **RPO de 5 min para doações:** é o menor valor alcançável com PITR de RDS
  sem replicação síncrona cross-region. Um RPO de segundos exigiria Aurora
  Global Database (indisponível no AWS Academy e ~3x mais caro) — o
  trade-off foi registrado e aceito pela diretoria.
- **RTO de 4 h:** tempo medido de `terraform apply` do ambiente espelho
  (~20 min para EKS + node group), restore de snapshot do RDS (~30–60 min
  para 20 GB), sincronização do ArgoCD (~10 min) e validação (~30 min),
  com folga para decisão humana e comunicação.
- **RPO 0 para infraestrutura e aplicações:** não existe estado só no cluster.
  Todo manifesto e todo recurso nascem de um commit.

---

## 4. Cenários de desastre e resposta

| # | Cenário | Probabilidade | Resposta | RTO real esperado |
|---|---|---|---|---|
| 1 | Pod/deployment degradado | Alta | **Automática** — self-healing faz rollout restart | < 1 min |
| 2 | Node perdido | Média | **Automática** — Kubernetes reagenda; anti-afinidade garante que o Hot Path não estava todo no node perdido | < 5 min |
| 3 | Deploy ruim | Média | `git revert` → ArgoCD reverte | < 10 min |
| 4 | Corrupção de dados / erro humano no banco | Baixa | RDS PITR para o instante anterior ao erro | < 2 h |
| 5 | Perda de uma AZ | Baixa | Subnets em 2 AZs; nodes reagendados na AZ sobrevivente | < 15 min |
| 6 | **Perda total da região** | Muito baixa | **Failover para us-west-2** (procedimento da seção 6) | **< 4 h** |
| 7 | Comprometimento de credenciais | Baixa | Rotação das chaves, `terraform apply` recria os Secrets, revisão de auditoria | < 2 h |
| 8 | Exclusão acidental do cluster | Baixa | `terraform apply` recria + `velero restore` | < 3 h |

---

## 5. Estratégia de DR implementada

Foram implementadas **as duas opções** previstas no desafio, porque elas
protegem coisas diferentes: o Velero protege o **estado**, o Terraform
modularizado protege a **capacidade de executar**.

### 5.1 Opção A — Velero com backup cross-region

`gitops/base/observability/08-velero.yaml` + `terraform/modules/dr-backup/`

| Item | Configuração |
|---|---|
| Destino | Bucket S3 **em us-west-2** (região diferente da primária, de propósito) |
| Proteção do bucket | Versionamento, criptografia AES256, acesso público bloqueado |
| Credenciais | Secret `velero-credentials` criado pelo Terraform — nunca vai para o Git |
| Backup diário | 03:00 UTC, todos os namespaces da plataforma, TTL 30 dias |
| **Backup horário** | **`donation-namespace`**, TTL 7 dias — sustenta o RPO de 1 h do estado do Hot Path |
| Ciclo de vida (FinOps) | STANDARD_IA após 30 dias, expiração em 90 dias |
| Monitoramento | Métricas do Velero raspadas pelo Prometheus via ServiceMonitor |

**Sobre snapshots de volume:** a plataforma **não usa PVC** — os dados vivem
em serviços gerenciados (RDS e DynamoDB), cada um com seu próprio mecanismo de
backup. O Velero cobre manifestos, ConfigMaps, Secrets e objetos do cluster.
Habilitar snapshots de EBS exigiria o EBS CSI driver e permissões de IAM que o
AWS Academy não concede. Quando houver PVC, basta ligar `snapshotsEnabled` e
`deployNodeAgent` no mesmo arquivo.

**Comandos de evidência:**

```bash
velero backup get                       # backups existentes e status
velero schedule get                     # agendamentos diário e horário
velero backup describe <nome> --details # o que foi capturado
velero backup logs <nome>
aws s3 ls s3://togglemaster-solidarytech-velero-backups/backups/ --region us-west-2
```

### 5.2 Opção B — Warm Standby por Terraform modularizado

`terraform/dr/` reutiliza **exatamente os mesmos módulos** do primário
(`terraform/modules/`), mudando apenas região, state e tamanho do node group.

```bash
# Levantar o ambiente espelho — um comando
terraform -chdir=terraform/dr init -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=solidarytech/fase5/dr/terraform.tfstate" \
  -backend-config="region=us-east-1"
terraform -chdir=terraform/dr apply -auto-approve
```

Ou, sem terminal, pelo pipeline: **Actions → Terraform DR (Warm Standby) →
Run workflow → action: `apply`**.

| Aspecto | Primário (us-east-1) | Espelho (us-west-2) |
|---|---|---|
| Node group | 3 nodes (min 2, max 5) | **1 node** (min 1, max 5) |
| Tag `DR` | `primary` | `standby` |
| Repositório GitOps | o mesmo | **o mesmo** |
| State do Terraform | `solidarytech/fase5/terraform.tfstate` | `solidarytech/fase5/dr/terraform.tfstate` |
| Custo em repouso | — | **US$ 0 (destruído)** |

O espelho apontar para o **mesmo repositório GitOps** é o ponto central: não
existem manifestos duplicados que possam divergir. O ArgoCD do espelho
converge para o mesmo estado desejado do primário.

---

## 6. Procedimento de failover (cenário 6)

**Decisão de acionar:** exclusiva do Líder de Incidente, após confirmar no
[AWS Health Dashboard](https://health.aws.amazon.com/health/status) que a
indisponibilidade regional é real e sem previsão de retorno em menos de 2 h.

| # | Ação | Comando / responsável | Tempo |
|---|---|---|---|
| 1 | Declarar P1 e comunicar diretoria e ONGs | Líder de Incidente | 10 min |
| 2 | Levantar o espelho | `terraform -chdir=terraform/dr apply -auto-approve` (ou workflow **Terraform DR**) | 20–25 min |
| 3 | Escalar para capacidade de produção | workflow **Terraform DR** com `node_desired_size: 3` | 5 min |
| 4 | Restaurar snapshot do RDS na região secundária | `aws rds restore-db-instance-from-db-snapshot` (snapshot copiado) | 30–60 min |
| 5 | Restaurar estado do cluster | `velero restore create --from-backup <mais-recente>` | 10 min |
| 6 | Aguardar o ArgoCD sincronizar as Applications | automático | 10 min |
| 7 | Validar os health checks | `curl http://<NLB-DR>/api/donation/health` | 10 min |
| 8 | Redirecionar o DNS (Route 53) para o NLB do espelho | Squad de plataforma | 5 min + TTL |
| 9 | Confirmar entrada de doações e comunicar normalização | Líder de Incidente | 15 min |
| | **Total** | | **≈ 2 h – 2 h 45 min** (dentro do RTO de 4 h) |

### Retorno à região primária (failback)

Só após 24 h de estabilidade confirmada da região original, em janela de baixo
tráfego: `terraform apply` no primário → restore dos dados a partir do
espelho (que passou a ser a fonte da verdade) → validação → redirecionamento
do DNS → `terraform -chdir=terraform/dr destroy`.

---

## 7. Testes do plano

| Teste | Frequência | Critério de sucesso |
|---|---|---|
| Restore de backup do Velero em namespace de teste | Mensal | Objetos restaurados idênticos ao original |
| PITR do RDS para instância temporária | Trimestral | Dados íntegros no instante escolhido |
| **Game day**: `apply` completo do espelho, medindo o tempo | Semestral | RTO real ≤ 4 h |
| Simulação de perda de node (`kubectl drain`) | Mensal | Zero erro 5xx no `donation-service` (PDB + anti-afinidade funcionando) |

> Um plano de DR nunca testado é uma suposição documentada. O game day
> semestral é o que transforma o RTO de promessa em medição.

---

## 8. Segurança — controles e riscos aceitos

### 8.1 Controles implementados

| Camada | Controle |
|---|---|
| Rede | Bancos e nodes em subnets **privadas**; Security Groups liberam 5432 apenas para o CIDR da VPC; nada exposto além do NLB |
| Dados em repouso | RDS `storage_encrypted`, DynamoDB SSE, S3 AES256, ECR AES256 |
| Segredos | Nenhuma credencial no Git: PagerDuty e Discord são placeholders substituídos em tempo de deploy; chaves do Datadog e do banco vêm de Secrets criados pelo Terraform ou pelo pipeline |
| Pipeline (DevSecOps) | Trivy (SCA + imagem), `gosec`, `bandit`; severidade CRITICAL/HIGH bloqueia o merge |
| Imagens | Multi-stage, usuário não-root, `scan_on_push` no ECR |
| Runtime | `allowPrivilegeEscalation: false`, `runAsNonRoot`, `capabilities.drop: [ALL]`; webhook com `readOnlyRootFilesystem` |
| RBAC | Self-healing com ClusterRole mínimo, restrito por regex de namespace |
| Auditoria | Todo deploy é um commit; toda mudança de infra é um plan revisável |
| Backup | Bucket versionado em outra região (resiliente a exclusão acidental e a ransomware) |

### 8.2 Riscos aceitos (limitações do AWS Academy)

| Risco | Por que existe | Mitigação atual | Correção em conta própria |
|---|---|---|---|
| Credenciais AWS estáticas em Secret do Kubernetes | Não é possível criar IAM Role/OIDC provider | Secret por namespace, token temporário (~4 h), rotação a cada sessão | **IRSA** — service account com role, sem chave |
| Sem Multi-AZ no RDS | Custo e limites do laboratório | Backup automático + PITR; failover por restore | `multi_az = true` |
| Senha do Grafana versionada | Ambiente efêmero, sem dados reais | Ambiente descartável, acesso só por port-forward | Secret externo / SSO |
| Prometheus em `emptyDir` | EBS CSI driver indisponível | Retenção de 7 dias; Datadog mantém o histórico longo | `storageSpec` com PVC gp3 |
| Sem WAF / TLS no ingress | Sem domínio nem certificado no laboratório | Rate limit de 50 rps no ingress | ACM + AWS WAF |
| Bucket de DR provisionado por AWS CLI, não pelo recurso nativo | A SCP da conta nega `s3:GetBucketObjectLockConfiguration` — chamada que o provider AWS faz no *read-after-create* de todo `aws_s3_bucket`. O bucket era criado, o apply falhava logo depois e ele nunca entrava no state | O módulo `dr-backup` usa `terraform_data` + `local-exec`: o bucket continua nascendo de `terraform apply`, com versionamento, SSE-AES256, bloqueio público, tags e lifecycle | Em conta sem a SCP, voltar aos recursos nativos `aws_s3_bucket*` |
| Imagens com registry explícito (`docker.io/...`) | O containerd do EKS resolve imagens sem registry para `public.ecr.aws`, onde o Velero não publica — o pod ficava em `ErrImagePull` | Todas as imagens de terceiros declaram o registry completo nos manifestos | Nenhuma — é boa prática manter, independente do ambiente |

Todos foram apresentados e aceitos formalmente como riscos de ambiente
acadêmico. Nenhum deles altera a arquitetura — são flags de configuração.

---

## 9. Papéis e contatos

| Papel | Responsabilidade | Acionamento |
|---|---|---|
| Líder de Incidente | Decide o failover, coordena, comunica | PagerDuty (plantão) |
| Squad de Plataforma | Executa Terraform, Velero e validações | Discord `#incidentes` |
| Diretoria de Tecnologia | Aprova failover com impacto financeiro | E-mail + telefone |
| Comunicação | Informa ONGs e doadores | Página de status |

**Escalonamento:** sem resposta do plantão em 15 min → aciona o segundo
plantonista; sem resposta em 30 min → aciona a Diretoria de Tecnologia.
