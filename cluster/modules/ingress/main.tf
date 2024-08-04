module "internal_ingress" {
  source        = "./modules/default"
  prefix        = "internal"
  suffix        = "internal"
  monitoring    = var.monitoring
  ingress_class = "nginx-internal"
  ip_pool       = var.ip_pool
}

module "external_ingress" {
  source        = "./modules/default"
  monitoring    = var.monitoring
  ingress_class = "nginx"
  extra_values  = [file("./values/nginx.external.extra.yaml")]
  ip_pool       = var.ip_pool
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
  version    = "1.15.1"
  repository = "https://charts.jetstack.io"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  set {
    name  = "crds.enabled"
    value = "true"
    type  = "auto"
  }

  set {
    name  = "replicaCount"
    value = "2"
    type  = "auto"
  }

  set {
    name  = "prometheus.enabled"
    value = var.monitoring
    type  = "auto"
  }

  set {
    name  = "prometheus.servicemonitor.enabled"
    value = var.monitoring
    type  = "auto"
  }
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
                "ingressClassName" = module.external_ingress.ingress_class
              }
            }
          }
        ]
      }
    }
  }
}
