# =============================================================================
# Módulo: DR Backup Storage (Opção A do requisito 4)
#
# Bucket S3 na REGIÃO SECUNDÁRIA que recebe os backups do Velero (manifestos
# do cluster + snapshots de volumes). Está em outra região de propósito: se a
# região primária ficar indisponível, o backup continua acessível para
# restaurar o ambiente no cluster espelho.
#
# O provider `aws` deste módulo é injetado com alias `aws.dr` pelo root module.
# =============================================================================

resource "aws_s3_bucket" "velero" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name = var.bucket_name
  })
}

# Versionamento: protege contra sobrescrita/corrupção e contra ransomware que
# tente apagar backups.
resource "aws_s3_bucket_versioning" "velero" {
  bucket = aws_s3_bucket.velero.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "velero" {
  bucket = aws_s3_bucket.velero.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Ciclo de vida (FinOps): backup só é caro quando fica em Standard para sempre.
#   - 30 dias  -> STANDARD_IA (menos da metade do preço por GB)
#   - 90 dias  -> expira (a retenção do Velero é de 30 dias por padrão)
#   - versões antigas expiram em 30 dias
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket_lifecycle_configuration" "velero" {
  bucket = aws_s3_bucket.velero.id

  rule {
    id     = "transicao-e-expiracao-de-backups"
    status = "Enabled"

    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.backup_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
