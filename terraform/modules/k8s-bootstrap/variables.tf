variable "services" {
  description = "Todos os microsserviços (vira 1 namespace por serviço)."
  type        = list(string)
  default     = ["ngo", "donation", "volunteer"]
}

variable "service_databases" {
  description = "Mapa serviço -> nome do banco RDS."
  type        = map(string)
  default = {
    ngo      = "ngodb"
    donation = "donationdb"
  }
}

variable "db_connection_urls" {
  description = "Mapa banco -> DATABASE_URL completa (output do módulo rds)."
  type        = map(string)
  sensitive   = true
}

variable "db_endpoints" {
  description = "Mapa banco -> host RDS (output do módulo rds)."
  type        = map(string)
}

variable "db_passwords" {
  description = "Mapa banco -> senha (output do módulo rds)."
  type        = map(string)
  sensitive   = true
}

variable "db_master_username" {
  description = "Usuário master comum das instâncias RDS."
  type        = string
}

variable "sqs_queue_url" {
  description = "URL da fila SQS de doações."
  type        = string
}

variable "dynamodb_table_name" {
  description = "Nome da tabela DynamoDB de voluntários."
  type        = string
  default     = "SolidaryTechVolunteers"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "aws_access_key_id" {
  type        = string
  description = "AWS Access Key ID"
  default     = ""
  sensitive   = true
}

variable "aws_secret_access_key" {
  type        = string
  description = "AWS Secret Access Key"
  default     = ""
  sensitive   = true
}

variable "aws_session_token" {
  type        = string
  description = "AWS Session Token (obrigatório em ambientes de Lab/AWS Academy)"
  default     = ""
  sensitive   = true
}
