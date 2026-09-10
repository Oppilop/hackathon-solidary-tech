# State SEPARADO do primário (key diferente) — um apply no DR nunca pode
# tocar no state de produção.
terraform {
  backend "s3" {
  }
}
