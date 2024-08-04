output "ingress_class" {
  value = yamldecode(helm_release.ingress_nginx.values[0]).controller.ingressClass
}

output "namespace" {
  value = kubernetes_namespace.nginx.metadata[0].name
}

output "notes" {
  value = helm_release.ingress_nginx.metadata[0].notes
}
