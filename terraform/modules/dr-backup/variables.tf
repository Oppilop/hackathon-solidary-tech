variable "bucket_name" {
  description = "Prefixo do bucket de backups do Velero. O account id é anexado para garantir unicidade global."
  type        = string
}

variable "region" {
  description = "Região onde o bucket é criado (a região de DR, diferente da primária)."
  type        = string
}

variable "backup_expiration_days" {
  description = "Dias até a expiração definitiva de um backup."
  type        = number
  default     = 90
}

variable "tags" {
  type    = map(string)
  default = {}
}
