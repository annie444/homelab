resource "kubernetes_namespace" "matrix" {
  metadata {
    annotations = {
      name = "matrix"
    }
    name = "matrix"
  }
}

module "eturnal" {
  source            = "./modules/eturnal"
  namespace         = kubernetes_namespace.matrix.metadata[0].name
  ingress_namespace = var.ingress_namespace
  ingress_class     = var.ingress_class
  cluster_issuer    = var.cluster_issuer
  eturnal_secret    = data.sops_file.matrix.data["eturnal.secret"]
}

resource "kubernetes_persistent_volume_claim" "matrix_media" {
  metadata {
    name      = "matrix-media"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim" "matrix_data" {
  metadata {
    name      = "matrix-data"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.storage_class
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

data "sops_file" "matrix" {
  source_file = "${path.module}/secrets/matrix.yaml"
}

resource "helm_release" "matrix_media_repo" {
  name       = "matrix-media-repo"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "matrix-media-repo"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/matrix-media-repo.values.yaml")
  ]

  set {
    name  = "persistence.existingClaim"
    value = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
  }

  set {
    name  = "externalPostgresql.host"
    value = var.postgresql_host
  }

  set_sensitive {
    name  = "externalPostgresql.password"
    value = data.sops_file.matrix.data["media.db.password"]
  }

  set {
    name  = "externalRedis.host"
    value = var.redis_host
  }

  set_sensitive {
    name  = "externalRedis.password"
    value = data.sops_file.matrix.data["redis.password"]
  }

  set {
    name  = "ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = var.cluster_issuer
  }

  set {
    name  = "ingress.className"
    value = var.ingress_class
  }

  set {
    name  = "podmonitor.enabled"
    value = var.monitoring
    type  = "auto"
  }
}

resource "helm_release" "matrix_synapse" {
  name       = "matrix-synapse"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "matrix-synapse"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/matrix-synapse.values.yaml"),
    yamlencode({
      workers = {
        default = {
          volumeMounts = [
            {
              name      = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
              mountPath = "/synapse/data/media"
            }
          ]
          volumes = [
            {
              name = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
              persistentVolumeClaim = {
                claimName = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
              }
            }
          ]
        }
      }
      synapse = {
        extraVolumeMounts = [
          {
            name      = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
            mountPath = "/synapse/data/media"
          }
        ]
        extraVolumes = [
          {
            name = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
            persistentVolumeClaim = {
              claimName = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
            }
          }
        ]
      }
    })
  ]

  set_sensitive {
    name  = "extraConfig.password_config.pepper"
    value = data.sops_file.matrix.data["synapse.pepper"]
  }

  set_sensitive {
    name  = "config.recaptcha.publicKey"
    value = data.sops_file.matrix.data["synapse.recaptcha.publickey"]
  }

  set_sensitive {
    name  = "config.recaptcha.privateKey"
    value = data.sops_file.matrix.data["synapse.recaptcha.privatekey"]
  }

  set_sensitive {
    name  = "config.turnSecret"
    value = data.sops_file.matrix.data["eturnal.secret"]
  }

  set_sensitive {
    name  = "config.registrationSharedSecret"
    value = data.sops_file.matrix.data["synapse.registrationsecret"]
  }

  set_sensitive {
    name  = "config.macaroonSecretKey"
    value = data.sops_file.matrix.data["synapse.macaroonsecret"]
  }

  set {
    name  = "persistence.existingClaim"
    value = kubernetes_persistent_volume_claim.matrix_data.metadata[0].name
  }

  set {
    name  = "externalPostgresql.host"
    value = var.postgresql_host
  }

  set_sensitive {
    name  = "externalPostgresql.password"
    value = data.sops_file.matrix.data["synapse.db.password"]
  }

  set_sensitive {
    name  = "externalRedis.password"
    value = data.sops_file.matrix.data["redis.password"]
  }

  set {
    name  = "externalRedis.host"
    value = var.redis_host
  }

  set {
    name  = "ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = var.cluster_issuer
  }

  set_sensitive {
    name  = "extraConfig.worker_replication_secret"
    value = data.sops_file.matrix.data["synapse.workerreplicationsecret"]
  }

}

resource "helm_release" "sliding_sync" {
  name       = "sliding-sync"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "sliding-sync-proxy"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = false
  max_history     = 10

  values = [
    file("${path.module}/values/sliding-sync.values.yaml")
  ]

  set_sensitive {
    name  = "syncSecret"
    value = data.sops_file.matrix.data["sync.secret"]
  }

  set {
    name  = "ingress.className"
    value = var.ingress_class
  }

  set {
    name  = "ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = var.cluster_issuer
  }

  set {
    name  = "externalPostgresql.host"
    value = var.postgresql_host
  }

  set_sensitive {
    name  = "externalPostgresql.password"
    value = data.sops_file.matrix.data["sync.db.password"]
  }
}

resource "helm_release" "synatainer" {
  name       = "synatainer"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "synatainer"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("${path.module}/values/synatainer.values.yaml")
  ]

  set {
    name  = "postgresql.host"
    value = var.postgresql_host
  }

  set_sensitive {
    name  = "postgresql.password"
    value = data.sops_file.matrix.data["synapse.db.password"]
  }

  set_sensitive {
    name  = "synapse.token"
    value = data.sops_file.matrix.data["synatainer.token"]
  }
}

resource "kubernetes_manifest" "matrix_podmonitor" {
  field_manager {
    force_conflicts = true
  }
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      labels = {
        "app.kubernetes.io/instance" = "matrix-synapse"
      }
      name      = "matrix-synapse"
      namespace = kubernetes_namespace.matrix.metadata[0].name
    }
    spec = {
      namespaceSelector = {
        matchNames = [
          kubernetes_namespace.matrix.metadata[0].name
        ]
      }

      podMetricsEndpoints = [
        {
          path     = "/_synapse/metrics"
          port     = "metrics"
          interval = "10s"
          relabelings = [
            {
              sourceLabels = ["__meta_kubernetes_pod_label_app_kubernetes_io_instance"]
              targetLabel  = "instance"
              action       = "Replace"
            },
            {
              sourceLabels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component"]
              targetLabel  = "component"
              action       = "Replace"
            },
            {
              sourceLabels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
              targetLabel  = "name"
              action       = "Replace"
            },
          ]
        }
      ]

      selector = {
        matchLabels = {
          "app.kubernetes.io/instance" = "matrix-synapse"
          "app.kubernetes.io/name"     = "matrix-synapse"
        }
      }
    }
  }
}

resource "kubernetes_manifest" "prometheus_matrix_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      labels = {
        prometheus = "prometheus"
        role       = "alert-rules"
      }
      name      = "prometheus-matrix-rules"
      namespace = kubernetes_namespace.matrix.metadata[0].name
    }
    spec = {
      groups = [
        {
          name = "synapse"
          rules = [
            {
              expr = "synapse_federation_client_sent_edus_total + 0"
              labels = {
                type = "EDU"
              }
              record = "synapse_federation_client_sent"
            },
            {
              expr = "synapse_federation_client_sent_pdu_destinations_count_total + 0"
              labels = {
                type = "PDU"
              }
              record = "synapse_federation_client_sent"
            },
            {
              expr = "sum(synapse_federation_client_sent_queries) by (job)"
              labels = {
                type = "Query"
              }
              record = "synapse_federation_client_sent"
            },
            {
              expr = "synapse_federation_server_received_edus_total + 0"
              labels = {
                type = "EDU"
              }
              record = "synapse_federation_server_received"
            },
            {
              expr = "synapse_federation_server_received_pdus_total + 0"
              labels = {
                type = "PDU"
              }
              record = "synapse_federation_server_received"
            },
            {
              expr = "sum(synapse_federation_server_received_queries) by (job)"
              labels = {
                type = "Query"
              }
              record = "synapse_federation_server_received"
            },
            {
              expr = "synapse_federation_transaction_queue_pending_edus + 0"
              labels = {
                type = "EDU"
              }
              record = "synapse_federation_transaction_queue_pending"
            },
            {
              expr = "synapse_federation_transaction_queue_pending_pdus + 0"
              labels = {
                type = "PDU"
              }
              record = "synapse_federation_transaction_queue_pending"
            },
            {
              expr = "sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_type=\"remote\"})"
              labels = {
                type = "remote"
              }
              record = "synapse_storage_events_persisted_by_source_type"
            },
            {
              expr = "sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_entity=\"*client*\",origin_type=\"local\"})"
              labels = {
                type = "local"
              }
              record = "synapse_storage_events_persisted_by_source_type"
            },
            {
              expr = "sum without(type, origin_type, origin_entity) (synapse_storage_events_persisted_events_sep_total{origin_entity!=\"*client*\",origin_type=\"local\"})"
              labels = {
                type = "bridges"
              }
              record = "synapse_storage_events_persisted_by_source_type"
            },
            {
              expr   = "sum without(origin_entity, origin_type) (synapse_storage_events_persisted_events_sep_total)"
              record = "synapse_storage_events_persisted_by_event_type"
            },
            {
              expr   = "sum without(type) (synapse_storage_events_persisted_events_sep_total)"
              record = "synapse_storage_events_persisted_by_origin"
            }
          ]
        }
      ]
    }
  }
}


