# =============================================================================
# Variáveis do ambiente PRIMÁRIO (região ativa).
# O ambiente espelho de DR usa as mesmas variáveis em terraform/dr/.
# =============================================================================

variable "aws_region" {
  description = "Região AWS primária (ativa)."
  type        = string
  default     = "us-east-1"
}

variable "dr_region" {
  description = "Região AWS secundária, usada para o bucket de backup do Velero e para o Warm Standby."
  type        = string
  default     = "us-west-2"
}

variable "project" {
  description = "Prefixo de nomenclatura usado em todos os recursos AWS."
  type        = string
  default     = "togglemaster"
}

variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
  default     = "togglemaster-eks-prod"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tags obrigatórias (FinOps) — requisito 2 do Hackathon.
# Aplicadas via `default_tags` no provider E via merge() em cada módulo, para
# que nenhum recurso escape da política de tagueamento.
# ─────────────────────────────────────────────────────────────────────────────
variable "finops_project" {
  description = "Tag obrigatória Project."
  type        = string
  default     = "SolidaryTech"
}

variable "finops_environment" {
  description = "Tag obrigatória Environment."
  type        = string
  default     = "Production"
}

variable "finops_cost_center" {
  description = "Tag obrigatória CostCenter."
  type        = string
  default     = "NGO-Core"
}

variable "finops_owner" {
  description = "Tag Owner — time responsável pelo custo (usada no rateio interno)."
  type        = string
  default     = "plataforma@solidarytech.org"
}

# ─────────────────────────────────────────────────────────────────────────────
# Serviços
# ─────────────────────────────────────────────────────────────────────────────
variable "services" {
  description = "Microsserviços da plataforma (viram ECR, namespace e Application no ArgoCD)."
  type        = list(string)
  default     = ["ngo", "donation", "volunteer"]
}

variable "infra_images" {
  description = "Imagens auxiliares que precisam de ECR mas NÃO geram namespace/Application próprios."
  type        = list(string)
  default     = ["self-healing-webhook"]
}

variable "service_databases" {
  description = "Mapa serviço -> nome do banco RDS. Serviços fora deste mapa não recebem banco."
  type        = map(string)
  default = {
    ngo      = "ngodb"
    donation = "donationdb"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Rightsizing (FinOps) — dimensionamento do node group
# ─────────────────────────────────────────────────────────────────────────────
variable "node_instance_types" {
  description = "Tipos de instância dos worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Nodes desejados. 3 x t3.medium comportam a stack de observabilidade + 3 serviços."
  type        = number
  default     = 3
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

# ─────────────────────────────────────────────────────────────────────────────
# Componentes opcionais
# ─────────────────────────────────────────────────────────────────────────────
variable "enable_elasticache" {
  description = <<-EOT
    Provisiona o ElastiCache (Redis). Mantido DESLIGADO por decisão de FinOps:
    nenhum dos 3 microsserviços da SolidaryTech usa cache hoje, e recurso ocioso
    é desperdício puro (~US$ 12/mês). Ligue quando existir consumidor real —
    ver docs/fase5/FINOPS.md, seção "Eliminação de desperdício".
  EOT
  type        = bool
  default     = false
}

variable "enable_cost_guardrails" {
  description = <<-EOT
    Cria AWS Budgets + Cost Anomaly Detection. Algumas contas de laboratório
    (AWS Academy) bloqueiam as APIs de Budgets/Cost Explorer; se o apply falhar
    com AccessDenied nesses recursos, defina como false e evidencie os guardrails
    pelo console conforme docs/fase5/FINOPS.md.
  EOT
  type        = bool
  default     = true
}

variable "enable_dr_backup_bucket" {
  description = <<-EOT
    Provisiona o bucket S3 de backup do Velero na dr_region.

    O módulo cria o bucket via AWS CLI (terraform_data + local-exec) em vez do
    recurso nativo aws_s3_bucket. Motivo: a SCP da conta nega
    s3:GetBucketObjectLockConfiguration, chamada que o provider faz no
    read-after-create de todo aws_s3_bucket — o bucket era criado mas o apply
    falhava e ele nunca entrava no state. Ver terraform/modules/dr-backup.

    As proteções aplicadas são as mesmas dos recursos nativos: versionamento,
    SSE-AES256, bloqueio de acesso público, tags e lifecycle de FinOps.
  EOT
  type        = bool
  default     = true
}

variable "monthly_budget_usd" {
  description = "Teto mensal de custo da plataforma (USD) usado no AWS Budgets."
  type        = number
  default     = 400
}

variable "budget_notification_email" {
  description = "E-mail que recebe os alertas de Budget e de anomalia de custo."
  type        = string
  default     = "plataforma@solidarytech.org"
}

# ─────────────────────────────────────────────────────────────────────────────
# Disaster Recovery
# ─────────────────────────────────────────────────────────────────────────────
variable "velero_bucket_name" {
  description = <<-EOT
    Nome do bucket S3 (na dr_region) que guarda os backups do Velero.
    ATENÇÃO: nomes de bucket são globais. Se alterar aqui, altere também em
    gitops/base/observability/08-velero.yaml (values.configuration.backupStorageLocation).
  EOT
  type        = string
  default     = "togglemaster-solidarytech-velero-backups"
}

variable "db_backup_retention_days" {
  description = "Retenção de backups automáticos do RDS. Define o piso do RPO das doações."
  type        = number
  default     = 7
}

# ─────────────────────────────────────────────────────────────────────────────
# GitOps
# ─────────────────────────────────────────────────────────────────────────────
variable "gitops_repo_url" {
  description = "URL HTTPS do repositório Git que o ArgoCD monitora."
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "HEAD"
}

variable "expose_argocd_lb" {
  description = "Expor argocd-server via LoadBalancer? (false = port-forward, recomendado em Academy)."
  type        = bool
  default     = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Credenciais (AWS Academy usa credenciais temporárias com session token)
# ─────────────────────────────────────────────────────────────────────────────
variable "aws_access_key_id" {
  type        = string
  description = "AWS Access Key ID"
  sensitive   = true
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS Secret Access Key"
  sensitive   = true
}

variable "aws_session_token" {
  type        = string
  description = "AWS Session Token (obrigatório em ambientes de Lab/AWS Academy)"
  default     = ""
  sensitive   = true
}
