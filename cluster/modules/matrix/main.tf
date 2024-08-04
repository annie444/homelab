resource "kubernetes_namespace" "matrix" {
  metadata {
    annotations = {
      name = "matrix"
    }
    name = "matrix"
  }
}

resource "kubernetes_persistent_volume_claim" "matrix_media" {
  metadata {
    name      = "matrix-media"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = var.media_storage_class
    resources {
      requests = {
        storage = "50Gi"
      }
    }
  }
}

data "sops_file" "matrix" {
  source_file = "./secrets/matrix.yaml"
}

resource "helm_release" "matrix_media_repo" {
  name       = "matrix-media-repo"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "matrix-media-repo"
  version    = "3.0.6"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("./values/matrix-media-repo.values.yaml")
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

resource "kubernetes_deployment" "eturnal" {
  metadata {
    name      = "eturnal"
    namespace = kubernetes_namespace.matrix.metadata[0].name
    labels = {
      app       = "eturnal"
      component = "turn_server"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app       = "eturnal"
        component = "turn_server"
      }
    }
    template {
      metadata {
        labels = {
          app       = "eturnal"
          component = "turn_server"
        }
      }
      spec {
        subdomain            = "eturnal"
        dns_policy           = "ClusterFirst"
        enable_service_links = true
        host_network         = false
        init_container {
          name              = "eturnal-certs"
          image             = "alpine"
          image_pull_policy = "IfNotPresent"
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
            privileged      = false
            run_as_non_root = true
            run_as_user     = 9000
            run_as_group    = 9000
          }
          command = [
            "sh",
            "-c",
            <<-EOT
            cp /secret/* /certs
            mv /certs/tls.crt /certs/crt.pem
            mv /certs/tls.key /certs/key.pem
            chmod -R 400 /certs/*
            chown 9000:9000 /certs/*
            EOT
          ]
          volume_mount {
            name       = "eturnal-certs-modified"
            mount_path = "/certs"
          }
          volume_mount {
            name       = "eturnal-certs"
            mount_path = "/secret"
          }
        }
        init_container {
          name              = "eturnal-config"
          image             = "alpine"
          image_pull_policy = "IfNotPresent"
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
            privileged      = false
            run_as_non_root = true
            run_as_user     = 9000
            run_as_group    = 9000
          }
          command = [
            "sh",
            "-c",
            <<-EOT
            cp /configmap/eturnal.yml /config
            chmod -R 600 /config/eturnal.yml
            chown 9000:9000 /config/eturnal.yml
            EOT
          ]
          volume_mount {
            name       = "eturnal-config-modified"
            mount_path = "/config"
          }
          volume_mount {
            name       = "eturnal-config"
            mount_path = "/configmap/eturnal.yml"
            sub_path   = "eturnal.yml"
          }
        }
        container {
          name              = "eturnal"
          image             = "ghcr.io/processone/eturnal:latest"
          image_pull_policy = "Always"
          volume_mount {
            name       = "eturnal-certs-modified"
            mount_path = "/opt/eturnal/tls"
            read_only  = true
          }
          volume_mount {
            name       = "eturnal-config-modified"
            mount_path = "/etc/eturnal.yml"
            sub_path   = "eturnal.yml"
            read_only  = true
          }
          port {
            container_port = 3478
            name           = "turn-udp"
            protocol       = "UDP"
          }
          port {
            container_port = 3478
            name           = "turn-tcp"
            protocol       = "TCP"
          }
          port {
            container_port = 5349
            name           = "turn-tls"
            protocol       = "TCP"
          }
          port {
            container_port = 5350
            name           = "turn-pp"
            protocol       = "TCP"
          }
          dynamic "port" {
            for_each = range(50000, 50500)
            content {
              container_port = port.value
              name           = "dynamic-${port.value}"
              protocol       = "UDP"
            }
          }
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
            privileged      = false
            run_as_non_root = true
            run_as_user     = 9000
            run_as_group    = 9000
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map.eturnal_env.metadata[0].name
            }
          }
          env_from {
            secret_ref {
              name = kubernetes_secret.eturnal_secret.metadata[0].name
            }
          }
          readiness_probe {
            tcp_socket {
              port = "turn-tcp"
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }
        }
        volume {
          name = "eturnal-config-modified"
          empty_dir {
            medium = "Memory"
          }
        }
        volume {
          name = "eturnal-certs-modified"
          empty_dir {
            medium = "Memory"
          }
        }
        volume {
          name = "eturnal-certs"
          secret {
            default_mode = "0640"
            secret_name  = kubernetes_secret.eturnal_tls.metadata[0].name
          }
        }
        volume {
          name = "eturnal-config"
          config_map {
            default_mode = "0640"
            name         = kubernetes_config_map.eturnal_config.metadata[0].name
          }
        }
      }
    }
  }
}

data "kubernetes_config_map" "udp_services" {
  metadata {
    name      = "ingress-ngnix-udp-services-configmap"
    namespace = var.ingress_namespace
    annotations = {
      app       = "ingress-nginx"
      component = "udp-services-configmap"
    }
  }
}

data "kubernetes_config_map" "tcp_services" {
  metadata {
    name      = "ingress-ngnix-tcp-services-configmap"
    namespace = var.ingress_namespace
    annotations = {
      app       = "ingress-nginx"
      component = "tcp-services-configmap"
    }
  }
}

locals {
  tcp_data = merge(data.kubernetes_config_map.tcp_services.data, {
    5350 = "${kubernetes_namespace.matrix.metadata[0].name}/${kubernetes_service.eturnal.metadata[0].name}:5350"
    5349 = "${kubernetes_namespace.matrix.metadata[0].name}/${kubernetes_service.eturnal.metadata[0].name}:5349"
    3478 = "${kubernetes_namespace.matrix.metadata[0].name}/${kubernetes_service.eturnal.metadata[0].name}:3478"
  })

  udp_data = merge(data.kubernetes_config_map.udp_services.data, {
    3478 = "${kubernetes_namespace.matrix.metadata[0].name}/${kubernetes_service.eturnal.metadata[0].name}:3478"
  })
}

resource "kubernetes_config_map" "tcp_services" {
  metadata {
    name        = data.kubernetes_config_map.tcp_services.metadata[0].name
    namespace   = data.kubernetes_config_map.tcp_services.metadata[0].namespace
    annotations = data.kubernetes_config_map.tcp_services.metadata[0].annotations
    labels      = data.kubernetes_config_map.tcp_services.metadata[0].labels
  }
  data = local.tcp_data
}

resource "kubernetes_config_map" "udp_services" {
  metadata {
    name        = data.kubernetes_config_map.udp_services.metadata[0].name
    namespace   = data.kubernetes_config_map.udp_services.metadata[0].namespace
    annotations = data.kubernetes_config_map.udp_services.metadata[0].annotations
    labels      = data.kubernetes_config_map.udp_services.metadata[0].labels
  }
  data = local.udp_data
}

resource "kubernetes_manifest" "eturnal_certificate" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = kubernetes_secret.eturnal_tls.metadata[0].name
      namespace = kubernetes_namespace.matrix.metadata[0].name
    }
    spec = {
      dnsNames = [
        "stun.jpeg.gay",
        "turn.jpeg.gay",
      ]
      duration = "2160h"
      issuerRef = {
        kind = "ClusterIssuer"
        name = "letsencrypt-prod"
      }
      privateKey = {
        algorithm      = "RSA"
        encoding       = "PKCS1"
        rotationPolicy = "Always"
        size           = 4096
      }
      renewBefore = "360h"
      secretName  = kubernetes_secret.eturnal_tls.metadata[0].name
    }
  }
}

resource "kubernetes_service" "eturnal" {
  metadata {
    name      = "eturnal"
    namespace = kubernetes_namespace.matrix.metadata[0].name
    labels = {
      app       = "eturnal"
      component = "turn_server"
    }
  }
  spec {
    type = "LoadBalancer"
    port {
      port        = 3478
      target_port = 3478
      protocol    = "UDP"
      name        = "turn-udp"
    }
    port {
      port        = 3478
      target_port = 3478
      protocol    = "TCP"
      name        = "turn-tcp"
    }
    port {
      port        = 5349
      target_port = 5349
      protocol    = "TCP"
      name        = "turn-tls"
    }
    port {
      port        = 5350
      target_port = 5350
      protocol    = "TCP"
      name        = "turn-pp"
    }
    selector = {
      app       = "eturnal"
      component = "turn_server"
    }
  }
}

resource "kubernetes_ingress_v1" "eturnal" {
  metadata {
    name      = "eturnal"
    namespace = kubernetes_namespace.matrix.metadata[0].name
    annotations = {
      "cert-manager.io/cluster-issuer" = var.cluster_issuer
    }
  }
  spec {
    rule {
      host = "turn.jpeg.gay"
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.eturnal.metadata[0].name
              port {
                name   = "turn-tcp"
                number = 3478
              }
            }
          }
        }
      }
    }
    rule {
      host = "stun.jpeg.gay"
      http {
        path {
          path = "/"
          backend {
            service {
              name = kubernetes_service.eturnal.metadata[0].name
              port {
                name   = "turn-tcp"
                number = 3478
              }
            }
          }
        }
      }
    }
    tls {
      hosts = [
        "turn.jpeg.gay",
        "stun.jpeg.gay"
      ]
      secret_name = kubernetes_secret.eturnal_tls.metadata[0].name
    }
  }
}

resource "kubernetes_config_map" "eturnal_config" {
  metadata {
    name      = "eturnal-config"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  data = {
    "eturnal.yml" = file("${path.module}/configs/eturnal.yml")
  }
}

resource "kubernetes_secret" "eturnal_secret" {
  metadata {
    name      = "eturnal-secret"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  data = {
    ETURNAL_SECRET = data.sops_file.matrix.data["eturnal.secret"]
  }
}

resource "kubernetes_secret" "eturnal_tls" {
  metadata {
    name      = "turn.jpeg.gay"
    namespace = kubernetes_namespace.matrix.metadata[0].name
    annotations = {
      "cert-manager.io/alt-names"        = "turn.jpeg.gay,stun.jpeg.gay"
      "cert-manager.io/certificate-name" = "turn.jpeg.gay,stun.jpeg.gay"
      "cert-manager.io/common-name"      = "turn.jpeg.gay"
      "cert-manager.io/ip-sans"          = ""
      "cert-manager.io/issuer-group"     = "cert-manager.io"
      "cert-manager.io/issuer-kind"      = "ClusterIssuer"
      "cert-manager.io/issuer-name"      = "letsencrypt-prod"
      "cert-manager.io/uri-sans"         = ""
    }
    labels = {
      "controller.cert-manager.io/fao" = "true"
    }
  }

  data = {
    "tls.crt" = ""
    "tls.key" = ""
  }

  type = "kubernetes.io/tls"
}

resource "kubernetes_config_map" "eturnal_env" {
  metadata {
    name      = "eturnal-env"
    namespace = kubernetes_namespace.matrix.metadata[0].name
  }

  data = {
    ERL_EPMD_ADDRESS       = "127.0.0.1"
    ETURNAL_RELAY_MIN_PORT = "50000"
    ETURNAL_RELAY_MAX_PORT = "50500"
  }
}

resource "helm_release" "matrix_synapse" {
  name       = "matrix-synapse"
  namespace  = kubernetes_namespace.matrix.metadata[0].name
  chart      = "matrix-synapse"
  version    = "3.9.9"
  repository = "https://ananace.gitlab.io/charts"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = [
    file("./values/matrix-synapse.values.yaml")
  ]

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
    name  = "persistence.storageClass"
    value = var.synapse_storage_class
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
    name  = "ingress.annotations.cert-manager\\.io/cluster-issuer"
    value = var.cluster_issuer
  }

  set_sensitive {
    name  = "extraConfig.worker_replication_secret"
    value = data.sops_file.matrix.data["synapse.workerreplicationsecret"]
  }

  set_list {
    name = "workers.default.volumeMounts"
    value = [
      yamlencode({
        "name"      = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
        "mountPath" = "/synapse/data/media"
      })
    ]
  }

  set_list {
    name = "synapse.extraVolumeMounts"
    value = [
      yamlencode({
        "name"      = kubernetes_persistent_volume_claim.matrix_media.metadata[0].name
        "mountPath" = "/synapse/data/media"
      })
    ]
  }
}


resource "kubernetes_manifest" "matrix_podmonitor" {
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
          path = "/_synapse/metrics"
          port = "metrics"
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
