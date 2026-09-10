variable "project" {
  type = string
}

variable "monthly_budget_usd" {
  description = "Teto mensal em USD."
  type        = number
}

variable "notification_email" {
  description = "Destinatário dos alertas de orçamento e anomalia."
  type        = string
}

variable "cost_tag_project" {
  description = "Valor da tag Project usada para filtrar o Budget."
  type        = string
  default     = "SolidaryTech"
}

variable "anomaly_impact_threshold_usd" {
  description = "Impacto mínimo (USD) para uma anomalia gerar notificação."
  type        = number
  default     = 20
}

variable "tags" {
  type    = map(string)
  default = {}
}
