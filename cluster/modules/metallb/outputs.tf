output "namespace" {
  value = kubernetes_namespace.metallb.metadata[0].name
}

output "ip_pool" {
  value = kubernetes_manifest.ip_pool.object.metadata.name
}

output "notes" {
  value = helm_release.metallb.metadata[0].notes
}
