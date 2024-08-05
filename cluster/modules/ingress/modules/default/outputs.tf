output "ingress_class" {
  value      = var.ingress_class
  depends_on = [helm_release.ingress_nginx]
}

output "namespace" {
  value = kubernetes_namespace.nginx.metadata[0].name
}

output "notes" {
  value = helm_release.ingress_nginx.metadata[0].notes
}
