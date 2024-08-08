resource "kubernetes_namespace" "vpn" {
  metadata {
    annotations = {
      name = "vpn"
    }
    name = "vpn"
  }
}


