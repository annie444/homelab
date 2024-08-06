resource "kubernetes_namespace" "redis" {
  metadata {
    annotations = {
      name = "redis"
    }
    name = "redis"
  }
}

data "sops_file" "redis" {
  source_file = "${path.module}/secrets/redis.yaml"
}

resource "kubernetes_secret" "redis" {
  metadata {
    name      = "redis-secret"
    namespace = kubernetes_namespace.redis.metadata[0].name
  }

  data = {
    "password" = data.sops_file.redis.data["password"]
  }

  type = "Opaque"
}

resource "helm_release" "redis" {
  name       = "redis"
  namespace  = kubernetes_namespace.redis.metadata[0].name
  chart      = "redis"
  repository = "https://charts.bitnami.com/bitnami"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("${path.module}/values/redis.values.yaml")],
    (
      var.monitoring ?
      [file("${path.module}/values/redis.monitoring.yaml")] :
      [file("${path.module}/values/redis.no-monitoring.yaml")]
    )
  )

  set {
    name  = "metrics.prometheusRule.namespace"
    value = var.prometheus_namespace
  }

  set {
    name  = "namespaceOverride"
    value = kubernetes_namespace.redis.metadata[0].name
  }

  set {
    name  = "auth.existingSecret"
    value = kubernetes_secret.redis.metadata[0].name
  }

  set {
    name  = "auth.existingSecretPasswordKey"
    value = "password"
  }

  set {
    name  = "global.defaultStorageClass"
    value = var.storage_class
  }

  set {
    name  = "master.persistence.storageClass"
    value = var.storage_class
  }

  set {
    name  = "replica.persistence.storageClass"
    value = var.storage_class
  }

  set {
    name  = "master.service.annotations.metallb\\.universe\\.tf/address-pool"
    value = var.ip_pool
  }

  set {
    name  = "replica.service.annotations.metallb\\.universe\\.tf/address-pool"
    value = var.ip_pool
  }

  set {
    name  = "master.service.annotations.metallb\\.universe\\.tf/allow-shared-ip"
    value = "redis-svc"
  }

  set {
    name  = "replica.service.annotations.metallb\\.universe\\.tf/allow-shared-ip"
    value = "redis-svc"
  }
}

data "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis-master"
    namespace = helm_release.redis.namespace
    labels = {
      "app.kubernetes.io/component" = "master"
    }
  }
}
