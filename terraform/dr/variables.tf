variable "aws_region" {
  description = "Região do ambiente espelho."
  type        = string
  default     = "us-west-2"
}

variable "project" {
  type    = string
  default = "togglemaster"
}

variable "cluster_name" {
  type    = string
  default = "togglemaster-eks-dr"
}

variable "kubernetes_version" {
  type    = string
  default = "1.31"
}

variable "finops_project" {
  type    = string
  default = "SolidaryTech"
}

variable "finops_environment" {
  type    = string
  default = "Production"
}

variable "finops_cost_center" {
  type    = string
  default = "NGO-Core"
}

variable "finops_owner" {
  type    = string
  default = "plataforma@solidarytech.org"
}

variable "services" {
  type    = list(string)
  default = ["ngo", "donation", "volunteer"]
}

variable "service_databases" {
  type = map(string)
  default = {
    ngo      = "ngodb"
    donation = "donationdb"
  }
}

# Warm standby dimensionado no mínimo — sobe para a capacidade do primário
# via `terraform apply -var node_desired_size=3` no momento do failover.
variable "node_instance_types" {
  type    = list(string)
  default = ["t3.medium"]
}

variable "node_desired_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "db_backup_retention_days" {
  type    = number
  default = 7
}

variable "gitops_repo_url" {
  description = "MESMO repositório GitOps do primário."
  type        = string
}

variable "gitops_revision" {
  type    = string
  default = "HEAD"
}

variable "aws_access_key_id" {
  type      = string
  sensitive = true
}

variable "aws_secret_access_key" {
  type      = string
  sensitive = true
}

variable "aws_session_token" {
  type      = string
  default   = ""
  sensitive = true
}
