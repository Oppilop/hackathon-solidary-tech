# =============================================================================
# SolidaryTech — ambiente PRIMÁRIO (us-east-1).
#
# Tudo é módulo: o mesmo conjunto é reutilizado por terraform/dr/ para levantar
# o ambiente espelho (Warm Standby) em outra região com 1 comando.
# =============================================================================

# Data source obrigatório no AWS Academy: a LabRole já existe e é a única role
# utilizável. O Terraform não cria nenhuma IAM Role ou Policy.
data "aws_iam_role" "labrole" {
  name = "LabRole"
}

locals {
  # ───────────────────────────────────────────────────────────────────────────
  # POLÍTICA DE TAGUEAMENTO (FinOps — requisito 2)
  # Estas tags entram em TODO recurso por dois caminhos independentes:
  #   1) provider.default_tags (providers.tf) — pega até o que esquecermos
  #   2) merge(var.tags, ...) dentro de cada módulo — explícito e auditável
  # ───────────────────────────────────────────────────────────────────────────
  common_tags = {
    Project     = var.finops_project     # SolidaryTech
    Environment = var.finops_environment # Production
    CostCenter  = var.finops_cost_center # NGO-Core
    Owner       = var.finops_owner
    ManagedBy   = "terraform"
    Phase       = "fase5-hackathon"
    Criticality = "high"
    DR          = "primary"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 1) Networking
# ─────────────────────────────────────────────────────────────────────────────
module "networking" {
  source = "./modules/networking"

  project      = var.project
  cluster_name = var.cluster_name
  tags         = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 2) ECR (3 microsserviços + webhook de self-healing)
# ─────────────────────────────────────────────────────────────────────────────
module "ecr" {
  source = "./modules/ecr"

  project  = var.project
  services = concat(var.services, var.infra_images)
  tags     = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 3) EKS (LabRole)
# ─────────────────────────────────────────────────────────────────────────────
module "eks" {
  source = "./modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.private_subnet_ids
  labrole_arn        = data.aws_iam_role.labrole.arn
  instance_types     = var.node_instance_types
  desired_size       = var.node_desired_size
  min_size           = var.node_min_size
  max_size           = var.node_max_size
  tags               = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 4) Dados: RDS (ngo, donation), DynamoDB (volunteer), SQS (eventos de doação)
# ─────────────────────────────────────────────────────────────────────────────
module "rds" {
  source = "./modules/rds"

  project                 = var.project
  vpc_id                  = module.networking.vpc_id
  vpc_cidr_block          = module.networking.vpc_cidr_block
  subnet_ids              = module.networking.private_subnet_ids
  databases               = values(var.service_databases)
  backup_retention_period = var.db_backup_retention_days
  tags                    = local.common_tags
}

module "dynamodb" {
  source = "./modules/dynamodb"

  table_name = "SolidaryTechVolunteers"
  # Point-in-Time Recovery ligado: é o que sustenta o RPO de 5 minutos dos
  # dados de voluntários declarado no PCN.
  enable_point_in_time_recovery = true
  tags                          = local.common_tags
}

module "sqs" {
  source = "./modules/sqs"

  queue_name = "solidary-donations"
  tags       = local.common_tags
}

# ElastiCache: desligado por padrão (decisão de FinOps — ver variables.tf).
module "elasticache" {
  source = "./modules/elasticache"
  count  = var.enable_elasticache ? 1 : 0

  project        = var.project
  vpc_id         = module.networking.vpc_id
  vpc_cidr_block = module.networking.vpc_cidr_block
  subnet_ids     = module.networking.private_subnet_ids
  tags           = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 5) FinOps — Budgets + Cost Anomaly Detection
# ─────────────────────────────────────────────────────────────────────────────
module "finops" {
  source = "./modules/finops"
  count  = var.enable_cost_guardrails ? 1 : 0

  project            = var.project
  monthly_budget_usd = var.monthly_budget_usd
  notification_email = var.budget_notification_email
  cost_tag_project   = var.finops_project
  tags               = local.common_tags
}

# ─────────────────────────────────────────────────────────────────────────────
# 6) Disaster Recovery — bucket de backup do Velero na região secundária
# ─────────────────────────────────────────────────────────────────────────────
module "dr_backup" {
  source = "./modules/dr-backup"

  bucket_name = var.velero_bucket_name
  tags = merge(local.common_tags, {
    Purpose = "disaster-recovery"
  })

  providers = {
    aws = aws.dr
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# 7) Bootstrap de objetos Kubernetes
# ─────────────────────────────────────────────────────────────────────────────
module "k8s_bootstrap" {
  source = "./modules/k8s-bootstrap"

  services            = var.services
  service_databases   = var.service_databases
  db_connection_urls  = module.rds.connection_urls
  db_endpoints        = module.rds.endpoints
  db_passwords        = module.rds.passwords
  db_master_username  = module.rds.master_username
  sqs_queue_url       = module.sqs.queue_url
  dynamodb_table_name = module.dynamodb.table_name
  aws_region          = var.aws_region

  aws_access_key_id     = var.aws_access_key_id
  aws_secret_access_key = var.aws_secret_access_key
  aws_session_token     = var.aws_session_token

  depends_on = [module.eks]
}

# ─────────────────────────────────────────────────────────────────────────────
# 8) ArgoCD (GitOps) — nenhum deploy manual via kubectl
# ─────────────────────────────────────────────────────────────────────────────
module "argocd" {
  source = "./modules/argocd"

  services        = var.services
  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  expose_lb       = var.expose_argocd_lb

  depends_on = [module.eks]
}
