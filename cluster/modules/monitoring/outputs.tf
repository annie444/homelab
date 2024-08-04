output "namespace" {
  value = kubernetes_namespace.monitoring.metadata[0].name
}

output "prometheus_notes" {
  value = helm_release.prometheus_stack.metadata[0].notes
}

output "alloy_notes" {
  value = helm_release.alloy.metadata[0].notes
}

output "loki_notes" {
  value = helm_release.loki.metadata[0].notes
}

output "prometheus_service_account" {
  value = data.kubernetes_service_account.prometheus.metadata[0].name
}

output "enabled" {
  value      = local.monitoring_enabled
  depends_on = [helm_release.prometheus_stack]
}
