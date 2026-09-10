# =============================================================================
# Módulo: FinOps guardrails
#
# Dois controles complementares:
#   1) AWS Budgets      -> teto de gasto com alertas em 80% (real), 100% (real)
#                          e 100% (previsto/forecast).
#   2) Cost Anomaly     -> detecção estatística de desvios de padrão de gasto,
#      Detection           independente do teto (pega um pico de US$ 30/dia
#                          mesmo que o mês ainda esteja dentro do orçamento).
#
# Ambos filtram pela tag Project=SolidaryTech, o que só funciona porque a
# política de tagueamento é aplicada em 100% dos recursos.
# =============================================================================

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-solidarytech-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    # O formato exigido pela API do Budgets é "user:<TagKey>$<TagValue>".
    # É preciso usar format() porque, em HCL, "$${" é a sequência de escape
    # que produz "${" literal — escrever "$$${var...}" NÃO interpola a variável.
    values = [format("user:Project$%s", var.cost_tag_project)]
  }

  # 80% do orçamento consumido — ainda dá tempo de reagir.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  # 100% do orçamento consumido.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  # Previsão de estouro (forecast) — este é o alerta que evita a surpresa no
  # fim do mês e alimenta o Relatório de Forecast do FINOPS.md.
  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }

  tags = var.tags
}

# ─────────────────────────────────────────────────────────────────────────────
# Cost Anomaly Detection
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ce_anomaly_monitor" "solidarytech" {
  name              = "${var.project}-solidarytech-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = var.tags
}

resource "aws_ce_anomaly_subscription" "solidarytech" {
  name      = "${var.project}-solidarytech-anomaly-alerts"
  frequency = "DAILY"

  monitor_arn_list = [aws_ce_anomaly_monitor.solidarytech.arn]

  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  # Só notifica anomalias com impacto absoluto acima do limiar, evitando
  # ruído de centavos (fadiga de alerta também existe em FinOps).
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_impact_threshold_usd)]
    }
  }

  tags = var.tags
}
