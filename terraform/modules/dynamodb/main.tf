# =============================================================================
# Módulo: DynamoDB
# Tabela SolidaryTechVolunteers consumida pelo volunteer-service.
# Modelo PAY_PER_REQUEST: sem capacidade provisionada ociosa — o padrão de
# acesso é imprevisível (picos após aparições na mídia), então pagar por
# requisição sai mais barato que provisionar para o pico. Ver FINOPS.md.
# =============================================================================

resource "aws_dynamodb_table" "volunteers" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "volunteer_id"

  attribute {
    name = "volunteer_id"
    type = "S"
  }

  # Point-in-Time Recovery: restaura a tabela em qualquer segundo dos últimos
  # 35 dias. É o mecanismo que sustenta o RPO dos dados de voluntários no PCN.
  point_in_time_recovery {
    enabled = var.enable_point_in_time_recovery
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(var.tags, {
    Name = var.table_name
  })
}
