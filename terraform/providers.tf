provider "aws" {
  region = var.aws_region

  # Bypasses para restrições da SCP do AWS Lab
  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region

  skip_metadata_api_check     = true
  skip_region_validation      = true
  skip_credentials_validation = true

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