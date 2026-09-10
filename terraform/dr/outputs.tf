output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "rds_endpoints" {
  description = "Endpoints do RDS espelho — alvo do restore de snapshot no failover."
  value       = module.rds.endpoints
}

output "failover_checklist" {
  description = "Passos do failover (ver docs/fase5/PCN-DR.md)."
  value = [
    "1. aws eks update-kubeconfig --region ${var.aws_region} --name ${var.cluster_name}",
    "2. velero restore create --from-backup <backup-mais-recente>",
    "3. Restaurar snapshot do RDS primário nas instâncias listadas em rds_endpoints",
    "4. Escalar o node group: terraform -chdir=terraform/dr apply -var node_desired_size=3",
    "5. Apontar o DNS/Route 53 para o NLB do cluster espelho",
  ]
}
