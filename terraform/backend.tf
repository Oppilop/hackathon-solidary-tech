# Backend S3 configurado via -backend-config no pipeline (bucket, key, region).
# Ver .github/workflows/terraform-infra.yml.
terraform {
  backend "s3" {
    skip_s3_checksum = true
  }
}
