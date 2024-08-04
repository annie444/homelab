resource "kubernetes_manifest" "service_rook_ceph_rook_ceph_mgr_dashboard_external_https" {
  manifest = {
    apiVersion = "v1"
    kind       = "Service"
    
  }
}
