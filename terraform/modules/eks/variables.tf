variable "cluster_name" {
  description = "Nome do cluster EKS."
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes para o control plane."
  type        = string
  default     = "1.30"
}

variable "vpc_id" {
  description = "ID da VPC onde o cluster será provisionado."
  type        = string
}

variable "subnet_ids" {
  description = "IDs das subnets (privadas) onde o cluster e nodes vão rodar."
  type        = list(string)
}

variable "labrole_arn" {
  description = "ARN da LabRole (AWS Academy). Usada tanto para cluster quanto para node group."
  type        = string
}

variable "instance_types" {
  description = "Tipos de instância dos worker nodes."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "ami_type" {
  description = <<-EOT
    AMI do node group. O default do provider (AL2_x86_64) foi descontinuado pela
    AWS e faz o CreateNodegroup falhar. Se a versão do Kubernetes for antiga
    demais para ter AMI publicada, suba var.kubernetes_version.
  EOT
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "desired_size" {
  description = "Quantidade desejada de nodes."
  type        = number
  default     = 3
}

variable "min_size" {
  description = "Mínimo de nodes."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Máximo de nodes."
  type        = number
  default     = 5
}

variable "tags" {
  description = "Tags comuns."
  type        = map(string)
  default     = {}
}
