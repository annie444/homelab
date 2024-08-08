resource "kubernetes_deployment" "terminal" {
  metadata {
    name      = "vpn-terminal"
    namespace = var.namespace
    labels = {
      app = "vpn-terminal"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "vpn-terminal"
      }
    }
    template {
      metadata {
        name = "vpn-terminal"
        labels = {
          name = "vpn-terminal"
          app  = "vpn-terminal"
          vpn  = "test-network-policy"
        }
      }
      spec {
        security_context {
          run_as_non_root = false
          run_as_user     = 0
        }
        container {
          name  = "network-tools"
          image = "jonlabelle/network-tools"
          tty   = true
          stdin = true
          command = [
            "/bin/bash"
          ]
          security_context {
            capabilities {
              add = [
                "NET_ADMIN",
                "NET_RAW"
              ]
            }
          }
        }
      }
    }
  }
}
