output "namespace" {
  value = kubernetes_namespace.postgresql.metadata[0].name
}

output "notes" {
  value = helm_release.postgresql.metadata[0].notes
}

output "host" {
  value = data.kubernetes_service_v1.postgresql.spec[0].cluster_ip
}
