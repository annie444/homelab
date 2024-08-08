resource "helm_release" "gateway" {
  name       = "vpn-gateway"
  chart      = "pod-gateway"
  namespace  = var.namespace
  repository = "https://angelnu.github.io/helm-charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10


}
