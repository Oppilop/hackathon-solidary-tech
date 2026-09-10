output "namespace" {
  value = kubernetes_namespace.argocd.metadata[0].name
}

output "applications" {
  description = "Applications registradas no ArgoCD."
  value = concat(
    var.services,
    ["solidarytech-ingress", "observability-stack", "self-healing-webhook"]
  )
}
