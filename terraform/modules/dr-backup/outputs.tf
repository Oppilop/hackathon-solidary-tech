output "bucket_name" {
  description = "Nome efetivo do bucket de backups do Velero (prefixo + account id)."
  value       = local.effective_bucket_name

  # Garante que quem consome o output só o leia depois do bucket existir.
  depends_on = [terraform_data.velero_bucket]
}

output "bucket_arn" {
  description = "ARN do bucket de backups do Velero."
  value       = "arn:aws:s3:::${local.effective_bucket_name}"

  depends_on = [terraform_data.velero_bucket]
}

output "bucket_region" {
  description = "Região do bucket — deve casar com o manifesto do Velero."
  value       = var.region
}
