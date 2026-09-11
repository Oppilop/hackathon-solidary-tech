provider "aws" {
  region = var.aws_region

  # Bypasses necessários para a SCP restritiva do AWS Academy / Vocareum
  skip_metadata_api_check = true

  # Ignora a chamada s3:GetBucketObjectLockConfiguration bloqueada pela SCP
  custom_lookups {
    skip_s3_bucket_object_lock_configuration = true
  }

  # Rede de segurança do tagueamento: qualquer recurso criado por qualquer
  # módulo herda as tags obrigatórias de FinOps.
  default_tags {
    tags = local.common_tags
  }
}

# Provider alternativo apontando para a região de DR. Usado pelo bucket de
# backup do Velero (cross-region) — requisito 4, Opção A.
provider "aws" {
  alias  = "dr"
  region = var.dr_region

  skip_metadata_api_check = true

  custom_lookups {
    skip_s3_bucket_object_lock_configuration = true
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "kubernetes" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(module.eks.cluster_ca_certificate, null) != null && try(module.eks.cluster_ca_certificate, "") != "" ? base64decode(module.eks.cluster_ca_certificate) : ""

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", try(module.eks.cluster_name, ""), "--region", var.aws_region]
  }
}

provider "kubectl" {
  host                   = try(module.eks.cluster_endpoint, "")
  cluster_ca_certificate = try(module.eks.cluster_ca_certificate, null) != null && try(module.eks.cluster_ca_certificate, "") != "" ? base64decode(module.eks.cluster_ca_certificate) : ""
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", try(module.eks.cluster_name, ""), "--region", var.aws_region]
  }
}

provider "helm" {
  kubernetes {
    host                   = try(module.eks.cluster_endpoint, "")
    cluster_ca_certificate = try(module.eks.cluster_ca_certificate, null) != null && try(module.eks.cluster_ca_certificate, "") != "" ? base64decode(module.eks.cluster_ca_certificate) : ""

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", try(module.eks.cluster_name, ""), "--region", var.aws_region]
    }
  }
}