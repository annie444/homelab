output "namespace" {
  value = kubernetes_namespace.element.metadata[0].name
}

output "notes" {
  value = helm_release.element_web.metadata[0].notes
}
