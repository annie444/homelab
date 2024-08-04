locals {
  prefix  = (var.prefix != null ? "${var.prefix}-" : "")
  suffix  = (var.suffix != null ? "-${var.suffix}" : "")
  ip_pool = (var.ip_pool != null ? [var.ip_pool] : [])
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
  version    = "4.11.1"
  repository = "https://kubernetes.github.io/ingress-nginx"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("./values/nginx.values.yaml")],
    (
      var.monitoring ?
      [file("./values/nginx.monitoring.yaml")] :
      [file("./values/nginx.no-monitoring.yaml")]
    ),
    var.extra_values
  )


  dynamic "set" {
    for_each = local.ip_pool
    iterator = ip_pool
    content {
      name  = "controller.service.annotations.metallb\\.universe\\.tf/address-pool"
      value = ip_pool.value
    }
  }

  set {
    name  = "controller.ingressClassResource.name"
    value = var.ingress_class
  }

  set {
    name  = "controller.ingressClass"
    value = var.ingress_class
  }
}
