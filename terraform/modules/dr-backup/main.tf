# =============================================================================
# Módulo: DR Backup Storage (Opção A do requisito 4)
#
# Bucket S3 na REGIÃO SECUNDÁRIA que recebe os backups do Velero (manifestos do
# cluster e objetos do Kubernetes). Está em outra região de propósito: se a
# região primária ficar indisponível, o backup continua acessível para
# restaurar o ambiente no cluster espelho.
#
# ─────────────────────────────────────────────────────────────────────────────
# POR QUE ESTE MÓDULO NÃO USA `aws_s3_bucket`
#
# A SCP da conta (AWS Academy) nega s3:GetBucketObjectLockConfiguration:
#
#   AccessDenied: ... is not authorized to perform:
#   s3:GetBucketObjectLockConfiguration ... with an explicit deny in a
#   service control policy
#
# O provider AWS faz essa chamada no READ de todo `aws_s3_bucket` — inclusive
# no read-after-create. Resultado: o CreateBucket funciona, mas o apply falha
# logo depois e o bucket nunca entra no state; no apply seguinte o Terraform
# tenta criá-lo de novo, em laço infinito. Não existe flag no provider que
# pule essa chamada.
#
# A saída é provisionar pelo AWS CLI, que chama apenas as APIs necessárias.
# O bucket continua nascendo de `terraform apply` (segue sendo IaC), com as
# mesmas proteções que os recursos nativos aplicariam. Em conta sem essa SCP,
# o caminho nativo volta a ser viável — ver README do módulo.
# ─────────────────────────────────────────────────────────────────────────────
# =============================================================================

data "aws_caller_identity" "current" {}

locals {
  # Sufixo com o account id: nomes de bucket S3 são globais e precisam ser
  # únicos entre todas as contas da AWS.
  effective_bucket_name = "${var.bucket_name}-${data.aws_caller_identity.current.account_id}"

  bucket_tags = jsonencode({
    TagSet = [for k, v in merge(var.tags, { Name = local.effective_bucket_name }) : {
      Key   = k
      Value = v
    }]
  })

  lifecycle_rules = jsonencode({
    Rules = [{
      # Backup só é caro quando fica em Standard para sempre (FinOps):
      #   30 dias -> STANDARD_IA · expira em backup_expiration_days
      ID     = "transicao-e-expiracao-de-backups"
      Status = "Enabled"
      Filter = {}
      Transitions = [{
        Days         = 30
        StorageClass = "STANDARD_IA"
      }]
      Expiration                     = { Days = var.backup_expiration_days }
      NoncurrentVersionExpiration    = { NoncurrentDays = 30 }
      AbortIncompleteMultipartUpload = { DaysAfterInitiation = 7 }
    }]
  })
}

resource "terraform_data" "velero_bucket" {
  # Guardado em `input` porque o provisioner de destroy só enxerga `self`.
  input = {
    bucket = local.effective_bucket_name
    region = var.region
  }

  # Recria a configuração quando nome, região ou políticas mudarem.
  triggers_replace = [
    local.effective_bucket_name,
    var.region,
    local.bucket_tags,
    local.lifecycle_rules,
  ]

  # ---------------------------------------------------------------------------
  # Criação — idempotente: se o bucket já existe, apenas reaplica as políticas.
  # ---------------------------------------------------------------------------
  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      BUCKET="${local.effective_bucket_name}"
      REGION="${var.region}"

      if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
        echo "bucket $BUCKET ja existe — reaplicando politicas"
      else
        echo "criando bucket $BUCKET em $REGION"
        aws s3api create-bucket \
          --bucket "$BUCKET" \
          --region "$REGION" \
          --create-bucket-configuration LocationConstraint="$REGION" >/dev/null
        aws s3api wait bucket-exists --bucket "$BUCKET" --region "$REGION"
      fi

      # Versionamento: protege contra sobrescrita, corrupção e ransomware.
      aws s3api put-bucket-versioning --bucket "$BUCKET" --region "$REGION" \
        --versioning-configuration Status=Enabled

      aws s3api put-bucket-encryption --bucket "$BUCKET" --region "$REGION" \
        --server-side-encryption-configuration \
        '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

      aws s3api put-public-access-block --bucket "$BUCKET" --region "$REGION" \
        --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

      aws s3api put-bucket-tagging --bucket "$BUCKET" --region "$REGION" \
        --tagging '${local.bucket_tags}'

      aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" --region "$REGION" \
        --lifecycle-configuration '${local.lifecycle_rules}'

      echo "bucket $BUCKET pronto (versionamento, SSE-AES256, acesso publico bloqueado, lifecycle e tags)"
    EOT
  }

  # ---------------------------------------------------------------------------
  # Destroy — esvazia (o bucket é versionado) e remove.
  # `on_failure = continue` para que um bucket já removido não trave o destroy.
  # ---------------------------------------------------------------------------
  provisioner "local-exec" {
    when        = destroy
    on_failure  = continue
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -uo pipefail
      BUCKET="${self.input.bucket}"
      REGION="${self.input.region}"

      if ! aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
        echo "bucket $BUCKET nao existe — nada a remover"
        exit 0
      fi

      echo "esvaziando $BUCKET (versoes e delete markers)"
      aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" \
        --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
          --output json --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true
      aws s3api delete-objects --bucket "$BUCKET" --region "$REGION" \
        --delete "$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
          --output json --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')" 2>/dev/null || true

      aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
      echo "bucket $BUCKET removido"
    EOT
  }
}
