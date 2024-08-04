resource "kubernetes_namespace" "element" {
  metadata {
    annotations = {
      name = "element"
    }
    name = "element"
  }
}

resource "helm_release" "element_web" {
  name       = "element-web"
  namespace  = kubernetes_namespace.element.metadata[0].name
  chart      = "element-web"
  version    = "1.3.28"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("../../values/element-web.values.yaml")
  ]

  set {
    name  = "ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = var.cluster_issuer
  }

  set {
    name  = "ingress.className"
    value = var.ingress_class
  }
}
