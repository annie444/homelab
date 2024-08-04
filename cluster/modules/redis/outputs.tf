output "namespace" {
  value = kubernetes_namespace.redis.metadata[0].name
}

output "notes" {
  value = helm_release.redis.metadata[0].notes
}

output "host" {
  value = data.kubernetes_service.redis.status[0].load_balancer[0].ingress[0].ip
}
