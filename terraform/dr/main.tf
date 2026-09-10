# =============================================================================
# SolidaryTech — ambiente ESPELHO (Warm Standby) — Opção B do requisito 4.
#
# Este root module reaproveita EXATAMENTE os mesmos módulos do ambiente
# primário (../modules), apenas com outra região, outro state e um node group
# reduzido. É isso que torna possível levantar a região secundária com um
# comando:
#
#     terraform -chdir=terraform/dr init -backend-config=...
#     terraform -chdir=terraform/dr apply -auto-approve
#
# Enquanto o desastre não acontece, o ambiente fica DESTRUÍDO (custo zero) ou
# com 1 node (warm). O que mantém o RPO é o backup contínuo:
#   - Velero  -> bucket S3 na dr_region (estado do cluster)
#   - RDS     -> snapshots automáticos (restaurar aqui no evento de DR)
#   - DynamoDB-> PITR
# =============================================================================

data "aws_iam_role" "labrole" {
  name = "LabRole"
}

locals {
  common_tags = {
    Project     = var.finops_project
    Environment = var.finops_environment
    CostCenter  = var.finops_cost_center
    Owner       = var.finops_owner
    ManagedBy   = "terraform"
    Phase       = "fase5-hackathon"
    Criticality = "high"
    DR          = "standby" # única tag que difere do primário
  }
}

module "networking" {
  source = "../modules/networking"

  project      = "${var.project}-dr"
  cluster_name = var.cluster_name
  tags         = local.common_tags
}

module "eks" {
  source = "../modules/eks"

  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id             = module.networking.vpc_id
  subnet_ids         = module.networking.private_subnet_ids
  labrole_arn        = data.aws_iam_role.labrole.arn

  # Warm standby: capacidade mínima. O HPA e o node group escalam quando o
  # tráfego for redirecionado para cá.
  instance_types = var.node_instance_types
  desired_size   = var.node_desired_size
  min_size       = 1
  max_size       = var.node_max_size

  tags = local.common_tags
}

module "rds" {
  source = "../modules/rds"

  project                 = "${var.project}-dr"
  vpc_id                  = module.networking.vpc_id
  vpc_cidr_block          = module.networking.vpc_cidr_block
  subnet_ids              = module.networking.private_subnet_ids
  databases               = values(var.service_databases)
  backup_retention_period = var.db_backup_retention_days
  tags                    = local.common_tags
}

module "dynamodb" {
  source = "../modules/dynamodb"

  table_name                    = "SolidaryTechVolunteers"
  enable_point_in_time_recovery = true
  tags                          = local.common_tags
}

module "sqs" {
  source = "../modules/sqs"

  queue_name = "solidary-donations"
  tags       = local.common_tags
}

module "k8s_bootstrap" {
  source = "../modules/k8s-bootstrap"

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

# O MESMO repositório GitOps. O cluster espelho converge para o mesmo estado
# desejado do primário sem nenhum manifesto duplicado.
module "argocd" {
  source = "../modules/argocd"

  services        = var.services
  gitops_repo_url = var.gitops_repo_url
  gitops_revision = var.gitops_revision
  expose_lb       = false

  depends_on = [module.eks]
}
