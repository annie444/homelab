output "internal_ingress" {
  value = module.internal_ingress.ingress_class
}

output "external_ingress" {
  value = module.external_ingress.ingress_class
}

output "cluster_issuer" {
  value = kubernetes_manifest.cluster_issuer.object.metadata.name
}

output "internal_namespace" {
  value = module.internal_ingress.namespace
}

output "external_namespace" {
  value = module.external_ingress.namespace
}

output "internal_notes" {
  value = module.internal_ingress.notes
}

output "external_notes" {
  value = module.external_ingress.notes
}

output "cert_notes" {
  value = helm_release.cert_manager.metadata[0].notes
}

output "cert_namespace" {
  value = kubernetes_namespace.cert_manager.metadata[0].name
}
