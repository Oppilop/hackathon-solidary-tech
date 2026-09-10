variable "bucket_name" {
  description = "Nome global do bucket de backups do Velero."
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
