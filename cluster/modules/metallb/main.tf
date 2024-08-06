resource "kubernetes_namespace" "metallb" {
  metadata {
    annotations = {
      name = "metallb-system"
    }
    name = "metallb-system"
  }
}

resource "helm_release" "metallb" {
  name       = "metallb"
  chart      = "metallb"
  repository = "https://metallb.github.io/metallb"
  namespace  = kubernetes_namespace.metallb.metadata[0].name

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = (var.monitoring ? [file("${path.module}/values/metallb.monitoring.yaml")] : [file("${path.module}/values/metallb.no-monitoring.yaml")])

  set {
    name  = "prometheus.serviceAccount"
    value = var.prometheus_service_account
    type  = "string"
  }

  set {
    name  = "prometheus.namespace"
    value = var.prometheus_namespace
    type  = "string"
  }
}

resource "kubernetes_manifest" "ip_pool" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta1"
    "kind"       = "IPAddressPool"
    "metadata" = {
      "name"      = "pool"
      "namespace" = helm_release.metallb.namespace
    }
    "spec" = {
      "addresses" = [
        "192.168.1.192/26"
      ]
    }
  }
}

resource "kubernetes_manifest" "ip_advertisement" {
  manifest = {
    "apiVersion" = "metallb.io/v1beta1"
    "kind"       = "L2Advertisement"
    "metadata" = {
      "name"      = "pool"
      "namespace" = helm_release.metallb.namespace
    }
    "spec" = {
      "ipAddressPools" = [
        kubernetes_manifest.ip_pool.object.metadata.name
      ]
    }
  }
}
