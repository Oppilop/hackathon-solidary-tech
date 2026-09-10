#!/bin/bash
# Executado automaticamente pelo LocalStack quando ele fica "ready".
# Cria os mesmos recursos que o Terraform cria na AWS real, para que o
# ambiente local tenha paridade com o cluster.
set -e

echo "[init-aws] Criando fila SQS solidary-donations..."
awslocal sqs create-queue --queue-name solidary-donations-dlq
awslocal sqs create-queue --queue-name solidary-donations

echo "[init-aws] Criando tabela DynamoDB SolidaryTechVolunteers..."
awslocal dynamodb create-table \
  --table-name SolidaryTechVolunteers \
  --attribute-definitions AttributeName=volunteer_id,AttributeType=S \
  --key-schema AttributeName=volunteer_id,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST

echo "[init-aws] Recursos locais prontos."
