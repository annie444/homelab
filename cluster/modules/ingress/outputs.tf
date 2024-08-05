output "internal_ingress" {
  value = module.default_ingress["internal"].ingress_class
}

output "external_ingress" {
  value = module.default_ingress["external"].ingress_class
}

output "cluster_issuer" {
  value = kubernetes_manifest.cluster_issuer.object.metadata.name
}

output "internal_namespace" {
  value = module.default_ingress["internal"].namespace
}

output "external_namespace" {
  value = module.default_ingress["external"].namespace
}

output "internal_notes" {
  value = module.default_ingress["internal"].notes
}

output "external_notes" {
  value = module.default_ingress["external"].notes
}

output "cert_notes" {
  value = helm_release.cert_manager.metadata[0].notes
}

output "cert_namespace" {
  value = kubernetes_namespace.cert_manager.metadata[0].name
}
