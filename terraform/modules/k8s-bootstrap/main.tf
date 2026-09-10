# =============================================================================
# Módulo: Bootstrap de objetos Kubernetes
#
# Cria o que NÃO pode morar no Git: namespaces, Secrets com credenciais e
# ConfigMaps derivados de outputs do Terraform (endpoints de RDS, URL da fila
# SQS, nome da tabela DynamoDB). Tudo o que é declarativo e não-sensível fica
# em gitops/ e é entregue pelo ArgoCD.
# =============================================================================

locals {
  # Serviço -> nome do banco (ex.: { ngo = "ngodb", donation = "donationdb" })
  db_services = var.service_databases
}

# -----------------------------------------------------------------------------
# Namespaces (1 por microsserviço)
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "app" {
  for_each = toset(var.services)

  metadata {
    name = "${each.key}-namespace"
    labels = {
      "app.kubernetes.io/part-of" = "solidarytech"
      "managed-by"                = "terraform"
      # Consumido pela política de tagueamento de custo do Datadog/Kubecost.
      "cost-center" = "ngo-core"
    }
  }
}

# -----------------------------------------------------------------------------
# Secret com as credenciais do banco — só nos namespaces que têm RDS
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "db" {
  for_each = local.db_services

  metadata {
    name      = "solidarytech-db-secret"
    namespace = kubernetes_namespace.app[each.key].metadata[0].name
  }

  data = {
    # Connection string completa (libpq) — é o que as apps esperam.
    DATABASE_URL = var.db_connection_urls[each.value]
    # Variáveis individuais, usadas pelo Job de init via psql.
    DB_HOST     = var.db_endpoints[each.value]
    DB_USER     = var.db_master_username
    DB_PASSWORD = var.db_passwords[each.value]
    DB_NAME     = each.value
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# ConfigMap compartilhado (não-sensível)
# -----------------------------------------------------------------------------
resource "kubernetes_config_map" "shared" {
  for_each = toset(var.services)

  metadata {
    name      = "solidarytech-config"
    namespace = kubernetes_namespace.app[each.key].metadata[0].name
  }

  data = {
    AWS_REGION         = var.aws_region
    AWS_SQS_URL        = var.sqs_queue_url
    AWS_DYNAMODB_TABLE = var.dynamodb_table_name

    NGO_SERVICE_URL       = "http://ngo-service.ngo-namespace.svc.cluster.local:8081"
    DONATION_SERVICE_URL  = "http://donation-service.donation-namespace.svc.cluster.local:8082"
    VOLUNTEER_SERVICE_URL = "http://volunteer-service.volunteer-namespace.svc.cluster.local:8083"
  }
}

# -----------------------------------------------------------------------------
# Credenciais AWS para os Pods.
#
# NOTA: em conta própria o correto seria IRSA (IAM Roles for Service Accounts),
# sem chave estática. No AWS Academy não é possível criar IAM Roles/OIDC
# provider, então usamos as credenciais temporárias do laboratório. Isso está
# registrado como risco aceito em docs/fase5/PCN-DR.md.
# -----------------------------------------------------------------------------
resource "kubernetes_secret" "aws_credentials" {
  for_each = kubernetes_namespace.app

  metadata {
    name      = "aws-credentials"
    namespace = each.value.metadata[0].name
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
    AWS_SESSION_TOKEN     = var.aws_session_token
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# Velero (Disaster Recovery, Opção A)
# O chart do Velero espera um Secret com um arquivo de credenciais no formato
# do AWS CLI, sob a chave `cloud`.
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "velero" {
  metadata {
    name = "velero"
    labels = {
      "app.kubernetes.io/part-of" = "solidarytech"
      "managed-by"                = "terraform"
      "purpose"                   = "disaster-recovery"
    }
  }
}

resource "kubernetes_secret" "velero_credentials" {
  metadata {
    name      = "velero-credentials"
    namespace = kubernetes_namespace.velero.metadata[0].name
  }

  data = {
    cloud = <<-EOT
      [default]
      aws_access_key_id=${var.aws_access_key_id}
      aws_secret_access_key=${var.aws_secret_access_key}
      aws_session_token=${var.aws_session_token}
    EOT
  }

  type = "Opaque"
}

# -----------------------------------------------------------------------------
# metrics-server — necessário para o HPA funcionar (todos os serviços têm HPA)
# -----------------------------------------------------------------------------
resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"
  version    = "3.12.1"

  set {
    name  = "args"
    value = "{--kubelet-insecure-tls,--kubelet-preferred-address-types=InternalIP}"
  }
}

# -----------------------------------------------------------------------------
# ingress-nginx — porta de entrada única da plataforma
# -----------------------------------------------------------------------------
resource "kubernetes_namespace" "ingress_nginx" {
  metadata {
    name = "ingress-nginx"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = kubernetes_namespace.ingress_nginx.metadata[0].name
  version    = "4.10.1"

  # LoadBalancer: o AWS Cloud Controller Manager cria um NLB e registra os
  # nodes do EKS como targets automaticamente.
  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  # Expõe métricas do controller para o Prometheus — a taxa de 5xx no edge é
  # usada como SLI complementar do donation-service.
  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  timeout       = 300
  wait          = true
  wait_for_jobs = true

  depends_on = [
    kubernetes_namespace.ingress_nginx,
    helm_release.metrics_server,
  ]
}
