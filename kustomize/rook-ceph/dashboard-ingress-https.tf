resource "kubernetes_manifest" "ingress_rook_ceph_rook_ceph_mgr_dashboard" {
  manifest = {
    apiVersion = "networking.k8s.io/v1"
    kind       = "Ingress"
    
  }
}
