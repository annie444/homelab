output "namespace" {
  value = kubernetes_namespace.redis.metadata[0].name
}

output "notes" {
  value = helm_release.redis.metadata[0].notes
}

output "host" {
  value = data.kubernetes_service_v1.redis.spec[0].cluster_ip
}
