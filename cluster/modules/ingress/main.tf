module "default_ingress" {
  for_each = tomap({
    external = {
      monitoring    = var.monitoring
      ingress_class = "nginx"
      extra_values  = [file("${path.module}/values/nginx.external.extra.yaml")]
      ip_pool       = var.ip_pool
      prefix        = null
      suffix        = null
    },
    internal = {
      monitoring    = var.monitoring
      ingress_class = "nginx-internal"
      extra_values  = []
      ip_pool       = var.ip_pool
      prefix        = "internal"
      suffix        = "internal"
    }
  })
  source        = "./modules/default"
  monitoring    = each.value.monitoring
  ingress_class = each.value.ingress_class
  extra_values  = each.value.extra_values
  ip_pool       = each.value.ip_pool
  prefix        = each.value.prefix
  suffix        = each.value.suffix
}

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    annotations = {
      name = "cert-manager"
    }
    name = "cert-manager"
  }
}

resource "helm_release" "cert_manager" {

  name       = "cert-manager"
  namespace  = kubernetes_namespace.cert_manager.metadata[0].name
  chart      = "cert-manager"
  repository = "https://charts.jetstack.io"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat([
    file("${path.module}/values/cert-manager.values.yaml")
  ], (
      var.monitoring ?
      [file("${path.module}/values/cert-manager.monitoring.yaml")] :
      [file("${path.module}/values/cert-maanger.no-monitoring.yaml")]
    ))
}

resource "kubernetes_manifest" "cluster_issuer" {
  manifest = {
    "apiVersion" = "cert-manager.io/v1"
    "kind"       = "ClusterIssuer"
    "metadata" = {
      "name" : "letsencrypt-prod"
    }
    "spec" = {
      "acme" = {
        "email"  = "annie.ehler.4@gmail.com"
        "server" = "https://acme-v02.api.letsencrypt.org/directory"
        "privateKeySecretRef" = {
          "name" = "letsencrypt-prod"
        }
        "solvers" = [
          {
            "http01" = {
              "ingress" = {
                "ingressClassName" = module.default_ingress["external"].ingress_class
              }
            }
          }
        ]
      }
    }
  }
}
