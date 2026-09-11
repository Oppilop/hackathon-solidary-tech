# =============================================================================
# Módulo: DR Backup Storage (Opção A do requisito 4)
# =============================================================================

# Obtém o ID da conta AWS para garantir unicidade global no S3
data "aws_caller_identity" "current" {}

locals {
  # Adiciona os dígitos da conta AWS ao final do nome base do bucket
  effective_bucket_name = "${var.bucket_name}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "velero" {
  bucket        = local.effective_bucket_name
  force_destroy = true

  tags = merge(var.tags, {
    Name = local.effective_bucket_name
  })
}

# Versionamento: protege contra sobrescrita/corrupção
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
# Ciclo de vida (FinOps)
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