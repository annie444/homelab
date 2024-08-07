resource "kubernetes_namespace" "monitoring" {
  metadata {
    annotations = {
      name = "monitoring"
    }
    name = "monitoring"
  }
}

data "sops_file" "grafana_credentials" {
  source_file = "${path.module}/secrets/grafana.yaml"
}

resource "kubernetes_secret" "grafana_admin_credentials" {
  metadata {
    name      = "grafana-admin-credentials"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    admin-user     = data.sops_file.grafana_credentials.data["user"]
    admin-password = data.sops_file.grafana_credentials.data["password"]
  }

  type = "Opaque"
}

resource "kubernetes_role" "grafana" {
  metadata {
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    name      = "grafana-secret"
  }
  rule {
    api_groups     = [""]
    resources      = ["secrets"]
    resource_names = [kubernetes_secret.grafana_admin_credentials.metadata[0].name]
    verbs          = ["get", "watch"]
  }
}

data "kubernetes_service_account" "grafana" {
  metadata {
    name      = "grafana"
    namespace = helm_release.prometheus_stack.namespace
  }
}

data "kubernetes_service_account" "prometheus" {
  metadata {
    name      = "prometheus-prometheus"
    namespace = helm_release.prometheus_stack.namespace
  }
}

resource "kubernetes_role_binding" "grafana" {
  metadata {
    name      = "grafana-secrets"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = data.kubernetes_service_account.grafana.metadata[0].name
    namespace = "monitoring"
  }
  role_ref {
    kind      = "Role"
    name      = kubernetes_role.grafana.metadata[0].name
    api_group = "rbac.authorization.k8s.io"
  }
}

resource "helm_release" "prometheus_stack" {
  name       = "prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  chart      = "kube-prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/prometheus-stack.values.yaml")
  ]
}

data "kubernetes_resource" "service_monitor" {
  api_version = "apiextensions.k8s.io/v1"
  kind        = "CustomResourceDefinition"

  metadata {
    name = "servicemonitors.monitoring.coreos.com"
  }

  depends_on = [helm_release.prometheus_stack]
}

data "kubernetes_resource" "pod_monitor" {
  api_version = "apiextensions.k8s.io/v1"
  kind        = "CustomResourceDefinition"

  metadata {
    name = "podmonitors.monitoring.coreos.com"
  }

  depends_on = [helm_release.prometheus_stack]
}

data "kubernetes_resource" "prometheus_rule" {
  api_version = "apiextensions.k8s.io/v1"
  kind        = "CustomResourceDefinition"

  metadata {
    name = "prometheusrules.monitoring.coreos.com"
  }

  depends_on = [helm_release.prometheus_stack]
}

locals {
  monitoring_enabled = (
    (
      data.kubernetes_resource.service_monitor.object.status.acceptedNames.kind == "ServiceMonitor" &&
      data.kubernetes_resource.pod_monitor.object.status.acceptedNames.kind == "PodMonitor" &&
      data.kubernetes_resource.prometheus_rule.object.status.acceptedNames.kind == "PrometheusRule"
    ) ? true : false
  )
}

resource "helm_release" "alloy" {
  name       = "alloy"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  chart      = "alloy"
  repository = "https://grafana.github.io/helm-charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("${path.module}/values/alloy.values.yaml")],
    (
      local.monitoring_enabled ?
      [file("${path.module}/values/alloy.monitoring.yaml")] :
      [file("${path.module}/values/alloy.no-monitoring.yaml")]
    )
  )

}

resource "helm_release" "loki" {
  name       = "loki"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  chart      = "loki"
  repository = "https://grafana.github.io/helm-charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/loki.values.yaml")
  ]
}

resource "kubernetes_ingress_v1" "grafana_external" {
  metadata {
    name = "grafana-external"
    annotations = {
      "cert-manager.io/cluster-issuer" = "letsencrypt-prod"
      "kubernetes.io/tls-acme"         = "true"
    }
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    ingress_class_name = "nginx"
    tls {
      hosts = [
        "grafana.jpeg.gay"
      ]
      secret_name = "grafana.jpeg.gay"
    }
    rule {
      host = "grafana.jpeg.gay"
      http {
        path {
          backend {
            service {
              name = "grafana"
              port {
                number = 80
              }
            }
          }
          path      = "/"
          path_type = "Prefix"
        }
      }
    }
  }
}
