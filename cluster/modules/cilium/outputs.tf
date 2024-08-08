output "namespace" {
  value = kubernetes_namespace.cilium.metadata[0].name
}

output "notes" {
  value = helm_release.cilium.metadata[0].notes
}
