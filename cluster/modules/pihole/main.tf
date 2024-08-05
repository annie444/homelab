resource "kubernetes_namespace" "pihole" {
  metadata {
    annotations = {
      name = "pihole-system"
    }
    name = "pihole-system"
  }
}

resource "helm_release" "pihole" {
  name       = "pihole"
  namespace  = kubernetes_namespace.pihole.metadata[0].name
  chart      = "pihole"
  version    = "2.26.1"
  repository = "https://mojo2600.github.io/pihole-kubernetes"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("${path.module}/values/pihole.values.yaml")],
    (
      var.monitoring ?
      [file("${path.module}/values/pihole.monitoring.yaml")] :
      [file("${path.module}/values/pihole.no-monitoring.yaml")]
    )
  )

  set {
    name  = "serviceWeb.annotations.metallb\\.universe\\.tf/address-pool"
    value = var.ip_pool
  }

  set {
    name  = "serviceDns.annotations.metallb\\.universe\\.tf/address-pool"
    value = var.ip_pool
  }
}

data "kubernetes_service" "pihole" {
  metadata {
    name      = "${helm_release.pihole.name}-web"
    namespace = kubernetes_namespace.pihole.metadata[0].name
  }
}

resource "helm_release" "externaldns_pihole" {
  name       = "externaldns-pihole"
  namespace  = kubernetes_namespace.pihole.metadata[0].name
  chart      = "external-dns"
  version    = "8.3.3"
  repository = "https://charts.bitnami.com/bitnami"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/externaldns.values.yaml")
  ]

  set_list {
    name = "ingressClassFilters"
    value = [
      var.ingress_class
    ]
  }

  set {
    name  = "pihole.server"
    value = "http://${data.kubernetes_service.pihole.spec[0].cluster_ip}"
  }
}
