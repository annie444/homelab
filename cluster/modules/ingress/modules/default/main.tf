locals {
  prefix = (var.prefix != null ? "${var.prefix}-" : "")
  suffix = (var.suffix != null ? "-${var.suffix}" : "")
}

resource "kubernetes_namespace" "nginx" {
  metadata {
    annotations = {
      name = "${local.prefix}nginx-system"
    }
    name = "${local.prefix}nginx-system"
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx${local.suffix}"
  namespace  = kubernetes_namespace.nginx.metadata[0].name
  chart      = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("${path.module}/values/nginx.values.yaml")],
    (
      var.monitoring ?
      [file("${path.module}/values/nginx.monitoring.yaml")] :
      [file("${path.module}/values/nginx.no-monitoring.yaml")]
    ),
    var.extra_values
  )

  set {
    name  = "controller.ingressClassResource.name"
    value = var.ingress_class
  }

  set {
    name  = "controller.ingressClass"
    value = var.ingress_class
  }
}


