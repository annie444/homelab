resource "kubernetes_namespace" "cilium" {
  metadata {
    annotations = {
      name = "cilium"
    }
    name = "cilium"
  }
}

resource "helm_release" "cilium" {
  name       = "cilium"
  chart      = "cilium"
  repository = "https://helm.cilium.io/"
  namespace  = kubernetes_namespace.cilium.metadata[0].name

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/cilium.values.yaml"),
    file("${path.module}/values/cilium.monitoring.yaml")
  ]
}

resource "kubernetes_manifest" "ip_pool" {
  depends_on = [helm_release.cilium]
  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumLoadBalancerIPPool"
    metadata = {
      name = "pool"
    }
    spec = {
      blocks = [
        { cidr = "192.168.1.192/26" }
      ]
    }
  }
}

resource "kubernetes_manifest" "ip_advertisement" {
  depends_on = [helm_release.cilium]
  manifest = {
    apiVersion = "cilium.io/v2alpha1"
    kind       = "CiliumL2AnnouncementPolicy"
    metadata = {
      name = "l2policy"
    }
    "spec" = {
      serviceSelector = {
        matchLabels = {
          ip-addr = "true"
        }
      }
      interfaces = [
        "^eth[0-9]+"
      ]
      externalIPs     = "true"
      loadBalancerIPs = "true"
    }
  }
}
