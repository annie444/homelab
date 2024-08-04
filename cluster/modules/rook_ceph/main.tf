resource "kubernetes_namespace" "rook_ceph" {
  metadata {
    annotations = {
      name = "rook-ceph"
    }
    name = "rook-ceph"
  }
}

resource "helm_release" "rook_ceph" {
  name       = "rook-ceph"
  namespace  = kubernetes_namespace.rook_ceph.metadata[0].name
  repository = "https://charts.rook.io/release"
  chart      = "rook-ceph"
  version    = "1.14.9"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("./values/rook-ceph.values.yaml")],
    (
      var.monitoring ?
      [file("./values/rook-ceph.monitoring.values.yaml")] :
      [file("./values/rook-ceph.no-monitoring.values.yaml")]
    )
  )
}

resource "helm_release" "rook_ceph_cluster" {
  name       = "rook-ceph-cluster"
  namespace  = helm_release.rook_ceph.namespace
  chart      = "rook-ceph-cluster"
  repository = "https://charts.rook.io/release"
  version    = "1.14.9"

  cleanup_on_fail = true
  lint            = true
  max_history     = 10

  values = concat(
    [file("./values/rook-ceph-cluster.values.yaml")],
    (
      var.monitoring ?
      [file("./values/rook-ceph-cluster.monitoring.values.yaml")] :
      [file("./values/rook-ceph-cluster.no-monitoring.values.yaml")]
    )
  )

  set {
    name  = "operatorNamespace"
    value = helm_release.rook_ceph.namespace
    type  = "string"
  }

  set {
    name  = "ingress.dashboard.ingressClassName"
    value = var.internal_ingress_class
    type  = "string"
  }
}

resource "kubernetes_manifest" "csi_metrics" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      labels = {
        team = "rook"
      }
      name      = "csi-metrics"
      namespace = kubernetes_namespace.rook_ceph.metadata[0].name
    }
    spec = {
      endpoints = [
        {
          interval = "5s"
          path     = "/metrics"
          port     = "csi-http-metrics"
        },
      ]
      namespaceSelector = {
        matchNames = [
          kubernetes_namespace.rook_ceph.metadata[0].name
        ]
      }
      selector = {
        matchLabels = {
          app = "csi-metrics"
        }
      }
    }
  }
}

resource "kubernetes_service" "ceph_dashboard" {
  metadata {
    labels = {
      app          = "rook-ceph-mgr"
      rook_cluster = "rook-ceph"
    }
    name      = "ceph-dashboard-external"
    namespace = kubernetes_namespace.rook_ceph.metadata[0].name
  }
  spec {
    port {
      name        = "dashboard"
      port        = 8443
      protocol    = "TCP"
      target_port = 8443
    }
    selector = {
      app          = "rook-ceph-mgr"
      rook_cluster = "rook-ceph"
    }
    session_affinity = "None"
    type             = "LoadBalancer"
  }
}

resource "kubernetes_ingress_v1" "ceph_dashboard" {
  metadata {
    annotations = {
      "cert-manager.io/cluster-issuer"               = var.cluster_issuer
      "kubernetes.io/tls-acme"                       = "true"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
      "nginx.ingress.kubernetes.io/server-snippet"   = <<-EOT
        proxy_ssl_verify off;
        
        EOT
    }
    name      = "rook-ceph-mgr-dashboard"
    namespace = kubernetes_namespace.rook_ceph.metadata[0].name
  }
  spec {
    ingress_class_name = var.external_ingress_class
    rule {
      host = "ceph.jpeg.gay"
      http {
        path {
          backend {
            service {
              name = "ceph-dashboard-external"
              port {
                name = "dashboard"
              }
            }
          }
          path      = "/"
          path_type = "Prefix"
        }
      }
    }
    tls {
      hosts = [
        "ceph.jpeg.gay",
      ]
      secret_name = "ceph.jpeg.gay"
    }
  }
}

resource "kubernetes_manifest" "ceph_prometheus_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      labels = {
        prometheus = "prometheus"
        role       = "alert-rules"
      }
      name      = "prometheus-ceph-external-rules"
      namespace = kubernetes_namespace.rook_ceph.metadata[0].name
    }
    spec = {
      groups = [
        {
          name = "persistent-volume-alert.rules"
          rules = [
            {
              alert = "PersistentVolumeUsageNearFull"
              annotations = {
                description    = "PVC {{ $labels.persistentvolumeclaim }} utilization has crossed 75%. Free up some space or expand the PVC."
                message        = "PVC {{ $labels.persistentvolumeclaim }} is nearing full. Data deletion or PVC expansion is required."
                severity_level = "warning"
                storage_type   = "ceph"
              }
              expr = <<-EOT
              (kubelet_volume_stats_used_bytes * on (namespace,persistentvolumeclaim) group_left(storageclass, provisioner) (kube_persistentvolumeclaim_info * on (storageclass)  group_left(provisioner) kube_storageclass_info {provisioner=~"(.*rbd.csi.ceph.com)|(.*cephfs.csi.ceph.com)"})) / (kubelet_volume_stats_capacity_bytes * on (namespace,persistentvolumeclaim) group_left(storageclass, provisioner) (kube_persistentvolumeclaim_info * on (storageclass)  group_left(provisioner) kube_storageclass_info {provisioner=~"(.*rbd.csi.ceph.com)|(.*cephfs.csi.ceph.com)"})) > 0.75
              
              EOT
              for  = "5s"
              labels = {
                severity = "warning"
              }
            },
            {
              alert = "PersistentVolumeUsageCritical"
              annotations = {
                description    = "PVC {{ $labels.persistentvolumeclaim }} utilization has crossed 85%. Free up some space or expand the PVC immediately."
                message        = "PVC {{ $labels.persistentvolumeclaim }} is critically full. Data deletion or PVC expansion is required."
                severity_level = "error"
                storage_type   = "ceph"
              }
              expr = <<-EOT
              (kubelet_volume_stats_used_bytes * on (namespace,persistentvolumeclaim) group_left(storageclass, provisioner) (kube_persistentvolumeclaim_info * on (storageclass)  group_left(provisioner) kube_storageclass_info {provisioner=~"(.*rbd.csi.ceph.com)|(.*cephfs.csi.ceph.com)"})) / (kubelet_volume_stats_capacity_bytes * on (namespace,persistentvolumeclaim) group_left(storageclass, provisioner) (kube_persistentvolumeclaim_info * on (storageclass)  group_left(provisioner) kube_storageclass_info {provisioner=~"(.*rbd.csi.ceph.com)|(.*cephfs.csi.ceph.com)"})) > 0.85
              
              EOT
              for  = "5s"
              labels = {
                severity = "critical"
              }
            },
          ]
        },
      ]
    }
  }
}

resource "kubernetes_manifest" "prometheusrule_rook_ceph_prometheus_ceph_rules" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PrometheusRule"
    metadata = {
      labels = {
        prometheus = "prometheus"
        role       = "alert-rules"
      }
      name      = "prometheus-ceph-rules"
      namespace = kubernetes_namespace.rook_ceph.metadata[0].name
    }
    spec = {
      groups = [
        {
          name = "cluster health"
          rules = [
            {
              alert = "CephHealthError"
              annotations = {
                description = "The cluster state has been HEALTH_ERROR for more than 5 minutes. Please check 'ceph health detail' for more information."
                summary     = "Ceph is in the ERROR state"
              }
              expr = "ceph_health_status == 2"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.2.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephHealthWarning"
              annotations = {
                description = "The cluster state has been HEALTH_WARN for more than 15 minutes. Please check 'ceph health detail' for more information."
                summary     = "Ceph is in the WARNING state"
              }
              expr = "ceph_health_status == 1"
              for  = "15m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "mon"
          rules = [
            {
              alert = "CephMonDownQuorumAtRisk"
              annotations = {
                description   = "{{ $min := query \"floor(count(ceph_mon_metadata) / 2) + 1\" | first | value }}Quorum requires a majority of monitors (x {{ $min }}) to be active. Without quorum the cluster will become inoperable, affecting all services and connected clients. The following monitors are down: {{- range query \"(ceph_mon_quorum_status == 0) + on(ceph_daemon) group_left(hostname) (ceph_mon_metadata * 0)\" }} - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }} {{- end }}"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-down"
                summary       = "Monitor quorum is at risk"
              }
              expr = <<-EOT
              (
                (ceph_health_detail{name="MON_DOWN"} == 1) * on() (
                  count(ceph_mon_quorum_status == 1) == bool (floor(count(ceph_mon_metadata) / 2) + 1)
                )
              ) == 1
              
              EOT
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.3.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephMonDown"
              annotations = {
                description   = <<-EOT
                {{ $down := query "count(ceph_mon_quorum_status == 0)" | first | value }}{{ $s := "" }}{{ if gt $down 1.0 }}{{ $s = "s" }}{{ end }}You have {{ $down }} monitor{{ $s }} down. Quorum is still intact, but the loss of an additional monitor will make your cluster inoperable.  The following monitors are down: {{- range query "(ceph_mon_quorum_status == 0) + on(ceph_daemon) group_left(hostname) (ceph_mon_metadata * 0)" }}   - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }} {{- end }}
                
                EOT
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-down"
                summary       = "One or more monitors down"
              }
              expr = <<-EOT
              count(ceph_mon_quorum_status == 0) <= (count(ceph_mon_metadata) - floor(count(ceph_mon_metadata) / 2) + 1)
              
              EOT
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephMonDiskspaceCritical"
              annotations = {
                description   = "The free space available to a monitor's store is critically low. You should increase the space available to the monitor(s). The default directory is /var/lib/ceph/mon-*/data/store.db on traditional deployments, and /var/lib/rook/mon-*/data/store.db on the mon pod's worker node for Rook. Look for old, rotated versions of *.log and MANIFEST*. Do NOT touch any *.sst files. Also check any other directories under /var/lib/rook and other directories on the same filesystem, often /var/log and /var/tmp are culprits. Your monitor hosts are; {{- range query \"ceph_mon_metadata\"}} - {{ .Labels.hostname }} {{- end }}"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-disk-crit"
                summary       = "Filesystem space on at least one monitor is critically low"
              }
              expr = "ceph_health_detail{name=\"MON_DISK_CRIT\"} == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.3.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephMonDiskspaceLow"
              annotations = {
                description   = "The space available to a monitor's store is approaching full (>70% is the default). You should increase the space available to the monitor(s). The default directory is /var/lib/ceph/mon-*/data/store.db on traditional deployments, and /var/lib/rook/mon-*/data/store.db on the mon pod's worker node for Rook. Look for old, rotated versions of *.log and MANIFEST*.  Do NOT touch any *.sst files. Also check any other directories under /var/lib/rook and other directories on the same filesystem, often /var/log and /var/tmp are culprits. Your monitor hosts are; {{- range query \"ceph_mon_metadata\"}} - {{ .Labels.hostname }} {{- end }}"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-disk-low"
                summary       = "Drive space on at least one monitor is approaching full"
              }
              expr = "ceph_health_detail{name=\"MON_DISK_LOW\"} == 1"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephMonClockSkew"
              annotations = {
                description   = "Ceph monitors rely on closely synchronized time to maintain quorum and cluster consistency. This event indicates that the time on at least one mon has drifted too far from the lead mon. Review cluster status with ceph -s. This will show which monitors are affected. Check the time sync status on each monitor host with 'ceph time-sync-status' and the state and peers of your ntpd or chrony daemon."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#mon-clock-skew"
                summary       = "Clock skew detected among monitors"
              }
              expr = "ceph_health_detail{name=\"MON_CLOCK_SKEW\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "osd"
          rules = [
            {
              alert = "CephOSDDownHigh"
              annotations = {
                description = "{{ $value | humanize }}% or {{ with query \"count(ceph_osd_up == 0)\" }}{{ . | first | value }}{{ end }} of {{ with query \"count(ceph_osd_up)\" }}{{ . | first | value }}{{ end }} OSDs are down (>= 10%). The following OSDs are down: {{- range query \"(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0\" }} - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }} {{- end }}"
                summary     = "More than 10% of OSDs are down"
              }
              expr = "count(ceph_osd_up == 0) / count(ceph_osd_up) * 100 >= 10"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDHostDown"
              annotations = {
                description = "The following OSDs are down: {{- range query \"(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0\" }} - {{ .Labels.hostname }} : {{ .Labels.ceph_daemon }} {{- end }}"
                summary     = "An OSD host is offline"
              }
              expr = "ceph_health_detail{name=\"OSD_HOST_DOWN\"} == 1"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.8"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDDown"
              annotations = {
                description   = <<-EOT
                {{ $num := query "count(ceph_osd_up == 0)" | first | value }}{{ $s := "" }}{{ if gt $num 1.0 }}{{ $s = "s" }}{{ end }}{{ $num }} OSD{{ $s }} down for over 5mins. The following OSD{{ $s }} {{ if eq $s "" }}is{{ else }}are{{ end }} down: {{- range query "(ceph_osd_up * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) == 0"}} - {{ .Labels.ceph_daemon }} on {{ .Labels.hostname }} {{- end }}
                
                EOT
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-down"
                summary       = "An OSD has been marked down"
              }
              expr = "ceph_health_detail{name=\"OSD_DOWN\"} == 1"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.2"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDNearFull"
              annotations = {
                description   = "One or more OSDs have reached the NEARFULL threshold. Use 'ceph health detail' and 'ceph osd df' to identify the problem. To resolve, add capacity to the affected OSD's failure domain, restore down/out OSDs, or delete unwanted data."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-nearfull"
                summary       = "OSD(s) running low on free space (NEARFULL)"
              }
              expr = "ceph_health_detail{name=\"OSD_NEARFULL\"} == 1"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.3"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDFull"
              annotations = {
                description   = "An OSD has reached the FULL threshold. Writes to pools that share the affected OSD will be blocked. Use 'ceph health detail' and 'ceph osd df' to identify the problem. To resolve, add capacity to the affected OSD's failure domain, restore down/out OSDs, or delete unwanted data."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-full"
                summary       = "OSD full, writes blocked"
              }
              expr = "ceph_health_detail{name=\"OSD_FULL\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.6"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDBackfillFull"
              annotations = {
                description   = "An OSD has reached the BACKFILL FULL threshold. This will prevent rebalance operations from completing. Use 'ceph health detail' and 'ceph osd df' to identify the problem. To resolve, add capacity to the affected OSD's failure domain, restore down/out OSDs, or delete unwanted data."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-backfillfull"
                summary       = "OSD(s) too full for backfill operations"
              }
              expr = "ceph_health_detail{name=\"OSD_BACKFILLFULL\"} > 0"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDTooManyRepairs"
              annotations = {
                description   = "Reads from an OSD have used a secondary PG to return data to the client, indicating a potential failing drive."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#osd-too-many-repairs"
                summary       = "OSD reports a high number of read errors"
              }
              expr = "ceph_health_detail{name=\"OSD_TOO_MANY_REPAIRS\"} == 1"
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDTimeoutsPublicNetwork"
              annotations = {
                description = "OSD heartbeats on the cluster's 'public' network (frontend) are running slow. Investigate the network for latency or loss issues. Use 'ceph health detail' to show the affected OSDs."
                summary     = "Network issues delaying OSD heartbeats (public network)"
              }
              expr = "ceph_health_detail{name=\"OSD_SLOW_PING_TIME_FRONT\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDTimeoutsClusterNetwork"
              annotations = {
                description = "OSD heartbeats on the cluster's 'cluster' network (backend) are slow. Investigate the network for latency issues on this subnet. Use 'ceph health detail' to show the affected OSDs."
                summary     = "Network issues delaying OSD heartbeats (cluster network)"
              }
              expr = "ceph_health_detail{name=\"OSD_SLOW_PING_TIME_BACK\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDInternalDiskSizeMismatch"
              annotations = {
                description   = "One or more OSDs have an internal inconsistency between metadata and the size of the device. This could lead to the OSD(s) crashing in future. You should redeploy the affected OSDs."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#bluestore-disk-size-mismatch"
                summary       = "OSD size inconsistency error"
              }
              expr = "ceph_health_detail{name=\"BLUESTORE_DISK_SIZE_MISMATCH\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephDeviceFailurePredicted"
              annotations = {
                description   = "The device health module has determined that one or more devices will fail soon. To review device status use 'ceph device ls'. To show a specific device use 'ceph device info <dev id>'. Mark the OSD out so that data may migrate to other OSDs. Once the OSD has drained, destroy the OSD, replace the device, and redeploy the OSD."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#id2"
                summary       = "Device(s) predicted to fail soon"
              }
              expr = "ceph_health_detail{name=\"DEVICE_HEALTH\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephDeviceFailurePredictionTooHigh"
              annotations = {
                description   = "The device health module has determined that devices predicted to fail can not be remediated automatically, since too many OSDs would be removed from the cluster to ensure performance and availability. Prevent data integrity issues by adding new OSDs so that data may be relocated."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#device-health-toomany"
                summary       = "Too many devices are predicted to fail, unable to resolve"
              }
              expr = "ceph_health_detail{name=\"DEVICE_HEALTH_TOOMANY\"} == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.7"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephDeviceFailureRelocationIncomplete"
              annotations = {
                description   = <<-EOT
                The device health module has determined that one or more devices will fail soon, but the normal process of relocating the data on the device to other OSDs in the cluster is blocked. 
                Ensure that the cluster has available free space. It may be necessary to add capacity to the cluster to allow data from the failing device to successfully migrate, or to enable the balancer.
                EOT
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#device-health-in-use"
                summary       = "Device failure is predicted, but unable to relocate data"
              }
              expr = "ceph_health_detail{name=\"DEVICE_HEALTH_IN_USE\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDFlapping"
              annotations = {
                description   = "OSD {{ $labels.ceph_daemon }} on {{ $labels.hostname }} was marked down and back up {{ $value | humanize }} times once a minute for 5 minutes. This may indicate a network issue (latency, packet loss, MTU mismatch) on the cluster network, or the public network if no cluster network is deployed. Check the network stats on the listed host(s)."
                documentation = "https://docs.ceph.com/en/latest/rados/troubleshooting/troubleshooting-osd#flapping-osds"
                summary       = "Network issues are causing OSDs to flap (mark each other down)"
              }
              expr = "(rate(ceph_osd_up[5m]) * on(ceph_daemon) group_left(hostname) ceph_osd_metadata) * 60 > 1"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.4"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephOSDReadErrors"
              annotations = {
                description   = "An OSD has encountered read errors, but the OSD has recovered by retrying the reads. This may indicate an issue with hardware or the kernel."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#bluestore-spurious-read-errors"
                summary       = "Device read errors detected"
              }
              expr = "ceph_health_detail{name=\"BLUESTORE_SPURIOUS_READ_ERRORS\"} == 1"
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGImbalance"
              annotations = {
                description = "OSD {{ $labels.ceph_daemon }} on {{ $labels.hostname }} deviates by more than 30% from average PG count."
                summary     = "PGs are not balanced across OSDs"
              }
              expr = <<-EOT
              abs(
                ((ceph_osd_numpg > 0) - on (job) group_left avg(ceph_osd_numpg > 0) by (job)) /
                on (job) group_left avg(ceph_osd_numpg > 0) by (job)
              ) * on (ceph_daemon) group_left(hostname) ceph_osd_metadata > 0.30
              
              EOT
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.4.5"
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "mds"
          rules = [
            {
              alert = "CephFilesystemDamaged"
              annotations = {
                description   = "Filesystem metadata has been corrupted. Data may be inaccessible. Analyze metrics from the MDS daemon admin socket, or escalate to support."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages#cephfs-health-messages"
                summary       = "CephFS filesystem is damaged."
              }
              expr = "ceph_health_detail{name=\"MDS_DAMAGE\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.5.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemOffline"
              annotations = {
                description   = "All MDS ranks are unavailable. The MDS daemons managing metadata are down, rendering the filesystem offline."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-all-down"
                summary       = "CephFS filesystem is offline"
              }
              expr = "ceph_health_detail{name=\"MDS_ALL_DOWN\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.5.3"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemDegraded"
              annotations = {
                description   = "One or more metadata daemons (MDS ranks) are failed or in a damaged state. At best the filesystem is partially available, at worst the filesystem is completely unusable."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages/#fs-degraded"
                summary       = "CephFS filesystem is degraded"
              }
              expr = "ceph_health_detail{name=\"FS_DEGRADED\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.5.4"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemMDSRanksLow"
              annotations = {
                description   = "The filesystem's 'max_mds' setting defines the number of MDS ranks in the filesystem. The current number of active MDS daemons is less than this value."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-up-less-than-max"
                summary       = "Ceph MDS daemon count is lower than configured"
              }
              expr = "ceph_health_detail{name=\"MDS_UP_LESS_THAN_MAX\"} > 0"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemInsufficientStandby"
              annotations = {
                description   = "The minimum number of standby daemons required by standby_count_wanted is less than the current number of standby daemons. Adjust the standby count or increase the number of MDS daemons."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages/#mds-insufficient-standby"
                summary       = "Ceph filesystem standby daemons too few"
              }
              expr = "ceph_health_detail{name=\"MDS_INSUFFICIENT_STANDBY\"} > 0"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemFailureNoStandby"
              annotations = {
                description   = "An MDS daemon has failed, leaving only one active rank and no available standby. Investigate the cause of the failure or add a standby MDS."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages/#fs-with-failed-mds"
                summary       = "MDS daemon failed, no further standby available"
              }
              expr = "ceph_health_detail{name=\"FS_WITH_FAILED_MDS\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.5.5"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephFilesystemReadOnly"
              annotations = {
                description   = "The filesystem has switched to READ ONLY due to an unexpected error when writing to the metadata pool. Either analyze the output from the MDS daemon admin socket, or escalate to support."
                documentation = "https://docs.ceph.com/en/latest/cephfs/health-messages#cephfs-health-messages"
                summary       = "CephFS filesystem in read only mode due to write error(s)"
              }
              expr = "ceph_health_detail{name=\"MDS_HEALTH_READ_ONLY\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.5.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "mgr"
          rules = [
            {
              alert = "CephMgrModuleCrash"
              annotations = {
                description   = "One or more mgr modules have crashed and have yet to be acknowledged by an administrator. A crashed module may impact functionality within the cluster. Use the 'ceph crash' command to determine which module has failed, and archive it to acknowledge the failure."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#recent-mgr-module-crash"
                summary       = "A manager module has recently crashed"
              }
              expr = "ceph_health_detail{name=\"RECENT_MGR_MODULE_CRASH\"} == 1"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.6.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephMgrPrometheusModuleInactive"
              annotations = {
                description = "The mgr/prometheus module at {{ $labels.instance }} is unreachable. This could mean that the module has been disabled or the mgr daemon itself is down. Without the mgr/prometheus module metrics and alerts will no longer function. Open a shell to an admin node or toolbox pod and use 'ceph -s' to to determine whether the mgr is active. If the mgr is not active, restart it, otherwise you can determine module status with 'ceph mgr module ls'. If it is not listed as enabled, enable it with 'ceph mgr module enable prometheus'."
                summary     = "The mgr/prometheus module is not available"
              }
              expr = "up{job=\"ceph\"} == 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.6.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "pgs"
          rules = [
            {
              alert = "CephPGsInactive"
              annotations = {
                description = "{{ $value }} PGs have been inactive for more than 5 minutes in pool {{ $labels.name }}. Inactive placement groups are not able to serve read/write requests."
                summary     = "One or more placement groups are inactive"
              }
              expr = "ceph_pool_metadata * on(pool_id,instance) group_left() (ceph_pg_total - ceph_pg_active) > 0"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGsUnclean"
              annotations = {
                description = "{{ $value }} PGs have been unclean for more than 15 minutes in pool {{ $labels.name }}. Unclean PGs have not recovered from a previous failure."
                summary     = "One or more placement groups are marked unclean"
              }
              expr = "ceph_pool_metadata * on(pool_id,instance) group_left() (ceph_pg_total - ceph_pg_clean) > 0"
              for  = "15m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.2"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGsDamaged"
              annotations = {
                description   = "During data consistency checks (scrub), at least one PG has been flagged as being damaged or inconsistent. Check to see which PG is affected, and attempt a manual repair if necessary. To list problematic placement groups, use 'rados list-inconsistent-pg <pool>'. To repair PGs use the 'ceph pg repair <pg_num>' command."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-damaged"
                summary       = "Placement group damaged, manual intervention needed"
              }
              expr = "ceph_health_detail{name=~\"PG_DAMAGED|OSD_SCRUB_ERRORS\"} == 1"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.4"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGRecoveryAtRisk"
              annotations = {
                description   = "Data redundancy is at risk since one or more OSDs are at or above the 'full' threshold. Add more capacity to the cluster, restore down/out OSDs, or delete unwanted data."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-recovery-full"
                summary       = "OSDs are too full for recovery"
              }
              expr = "ceph_health_detail{name=\"PG_RECOVERY_FULL\"} == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.5"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGUnavailableBlockingIO"
              annotations = {
                description   = "Data availability is reduced, impacting the cluster's ability to service I/O. One or more placement groups (PGs) are in a state that blocks I/O."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-availability"
                summary       = "PG is unavailable, blocking I/O"
              }
              expr = "((ceph_health_detail{name=\"PG_AVAILABILITY\"} == 1) - scalar(ceph_health_detail{name=\"OSD_DOWN\"})) == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.3"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGBackfillAtRisk"
              annotations = {
                description   = "Data redundancy may be at risk due to lack of free space within the cluster. One or more OSDs have reached the 'backfillfull' threshold. Add more capacity, or delete unwanted data."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-backfill-full"
                summary       = "Backfill operations are blocked due to lack of free space"
              }
              expr = "ceph_health_detail{name=\"PG_BACKFILL_FULL\"} == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.7.6"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGNotScrubbed"
              annotations = {
                description   = "One or more PGs have not been scrubbed recently. Scrubs check metadata integrity, protecting against bit-rot. They check that metadata is consistent across data replicas. When PGs miss their scrub interval, it may indicate that the scrub window is too small, or PGs were not in a 'clean' state during the scrub window. You can manually initiate a scrub with: ceph pg scrub <pgid>"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-not-scrubbed"
                summary       = "Placement group(s) have not been scrubbed"
              }
              expr = "ceph_health_detail{name=\"PG_NOT_SCRUBBED\"} == 1"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGsHighPerOSD"
              annotations = {
                description   = <<-EOT
                The number of placement groups per OSD is too high (exceeds the mon_max_pg_per_osd setting).
                 Check that the pg_autoscaler has not been disabled for any pools with 'ceph osd pool autoscale-status', and that the profile selected is appropriate. You may also adjust the target_size_ratio of a pool to guide the autoscaler based on the expected relative size of the pool ('ceph osd pool set cephfs.cephfs.meta target_size_ratio .1') or set the pg_autoscaler mode to 'warn' and adjust pg_num appropriately for one or more pools.
                EOT
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks/#too-many-pgs"
                summary       = "Placement groups per OSD is too high"
              }
              expr = "ceph_health_detail{name=\"TOO_MANY_PGS\"} == 1"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPGNotDeepScrubbed"
              annotations = {
                description   = "One or more PGs have not been deep scrubbed recently. Deep scrubs protect against bit-rot. They compare data replicas to ensure consistency. When PGs miss their deep scrub interval, it may indicate that the window is too small or PGs were not in a 'clean' state during the deep-scrub window."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pg-not-deep-scrubbed"
                summary       = "Placement group(s) have not been deep scrubbed"
              }
              expr = "ceph_health_detail{name=\"PG_NOT_DEEP_SCRUBBED\"} == 1"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "nodes"
          rules = [
            {
              alert = "CephNodeRootFilesystemFull"
              annotations = {
                description = "Root volume is dangerously full: {{ $value | humanize }}% free."
                summary     = "Root filesystem is dangerously full"
              }
              expr = "node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"} * 100 < 5"
              for  = "5m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.8.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephNodeNetworkPacketDrops"
              annotations = {
                description = "Node {{ $labels.instance }} experiences packet drop > 0.5% or > 10 packets/s on interface {{ $labels.device }}."
                summary     = "One or more NICs reports packet drops"
              }
              expr = <<-EOT
              (
                rate(node_network_receive_drop_total{device!="lo"}[1m]) +
                rate(node_network_transmit_drop_total{device!="lo"}[1m])
              ) / (
                rate(node_network_receive_packets_total{device!="lo"}[1m]) +
                rate(node_network_transmit_packets_total{device!="lo"}[1m])
              ) >= 0.0050000000000000001 and (
                rate(node_network_receive_drop_total{device!="lo"}[1m]) +
                rate(node_network_transmit_drop_total{device!="lo"}[1m])
              ) >= 10
              
              EOT
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.8.2"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephNodeNetworkPacketErrors"
              annotations = {
                description = "Node {{ $labels.instance }} experiences packet errors > 0.01% or > 10 packets/s on interface {{ $labels.device }}."
                summary     = "One or more NICs reports packet errors"
              }
              expr = <<-EOT
              (
                rate(node_network_receive_errs_total{device!="lo"}[1m]) +
                rate(node_network_transmit_errs_total{device!="lo"}[1m])
              ) / (
                rate(node_network_receive_packets_total{device!="lo"}[1m]) +
                rate(node_network_transmit_packets_total{device!="lo"}[1m])
              ) >= 0.0001 or (
                rate(node_network_receive_errs_total{device!="lo"}[1m]) +
                rate(node_network_transmit_errs_total{device!="lo"}[1m])
              ) >= 10
              
              EOT
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.8.3"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephNodeNetworkBondDegraded"
              annotations = {
                description = "Bond {{ $labels.master }} is degraded on Node {{ $labels.instance }}."
                summary     = "Degraded Bond on Node {{ $labels.instance }}"
              }
              expr = <<-EOT
              node_bonding_slaves - node_bonding_active != 0
              
              EOT
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephNodeDiskspaceWarning"
              annotations = {
                description = "Mountpoint {{ $labels.mountpoint }} on {{ $labels.nodename }} will be full in less than 5 days based on the 48 hour trailing fill rate."
                summary     = "Host filesystem free space is getting low"
              }
              expr = "predict_linear(node_filesystem_free_bytes{device=~\"/.*\"}[2d], 3600 * 24 * 5) *on(instance) group_left(nodename) node_uname_info < 0"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.8.4"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephNodeInconsistentMTU"
              annotations = {
                description = "Node {{ $labels.instance }} has a different MTU size ({{ $value }}) than the median of devices named {{ $labels.device }}."
                summary     = "MTU settings across Ceph hosts are inconsistent"
              }
              expr = "node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0) ==  scalar(    max by (device) (node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0)) !=      quantile by (device) (.5, node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0))  )or node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0) ==  scalar(    min by (device) (node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0)) !=      quantile by (device) (.5, node_network_mtu_bytes * (node_network_up{device!=\"lo\"} > 0))  )"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "pools"
          rules = [
            {
              alert = "CephPoolGrowthWarning"
              annotations = {
                description = "Pool '{{ $labels.name }}' will be full in less than 5 days assuming the average fill-up rate of the past 48 hours."
                summary     = "Pool growth rate may soon exceed capacity"
              }
              expr = "(predict_linear(ceph_pool_percent_used[2d], 3600 * 24 * 5) * on(pool_id, instance, pod) group_right() ceph_pool_metadata) >= 95"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.9.2"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPoolBackfillFull"
              annotations = {
                description = "A pool is approaching the near full threshold, which will prevent recovery/backfill operations from completing. Consider adding more capacity."
                summary     = "Free space in a pool is too low for recovery/backfill"
              }
              expr = "ceph_health_detail{name=\"POOL_BACKFILLFULL\"} > 0"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPoolFull"
              annotations = {
                description   = "A pool has reached its MAX quota, or OSDs supporting the pool have reached the FULL threshold. Until this is resolved, writes to the pool will be blocked. Pool Breakdown (top 5) {{- range query \"topk(5, sort_desc(ceph_pool_percent_used * on(pool_id) group_right ceph_pool_metadata))\" }} - {{ .Labels.name }} at {{ .Value }}% {{- end }} Increase the pool's quota, or add capacity to the cluster first then increase the pool's quota (e.g. ceph osd pool set quota <pool_name> max_bytes <bytes>)"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#pool-full"
                summary       = "Pool is full - writes are blocked"
              }
              expr = "ceph_health_detail{name=\"POOL_FULL\"} > 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.9.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephPoolNearFull"
              annotations = {
                description = "A pool has exceeded the warning (percent full) threshold, or OSDs supporting the pool have reached the NEARFULL threshold. Writes may continue, but you are at risk of the pool going read-only if more capacity isn't made available. Determine the affected pool with 'ceph df detail', looking at QUOTA BYTES and STORED. Increase the pool's quota, or add capacity to the cluster first then increase the pool's quota (e.g. ceph osd pool set quota <pool_name> max_bytes <bytes>). Also ensure that the balancer is active."
                summary     = "One or more Ceph pools are nearly full"
              }
              expr = "ceph_health_detail{name=\"POOL_NEAR_FULL\"} > 0"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "healthchecks"
          rules = [
            {
              alert = "CephSlowOps"
              annotations = {
                description   = "{{ $value }} OSD requests are taking too long to process (osd_op_complaint_time exceeded)"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#slow-ops"
                summary       = "OSD operations are slow to complete"
              }
              expr = "ceph_healthcheck_slow_ops > 0"
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephDaemonSlowOps"
              annotations = {
                description   = "{{ $labels.ceph_daemon }} operations are taking too long to process (complaint time exceeded)"
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#slow-ops"
                summary       = "{{ $labels.ceph_daemon }} operations are slow to complete"
              }
              expr = "ceph_daemon_health_metrics{type=\"SLOW_OPS\"} > 0"
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "hardware"
          rules = [
            {
              alert = "HardwareStorageError"
              annotations = {
                description = "Some storage devices are in error. Check `ceph health detail`."
                summary     = "Storage devices error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_STORAGE\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "HardwareMemoryError"
              annotations = {
                description = "DIMM error(s) detected. Check `ceph health detail`."
                summary     = "DIMM error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_MEMORY\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "HardwareProcessorError"
              annotations = {
                description = "Processor error(s) detected. Check `ceph health detail`."
                summary     = "Processor error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_PROCESSOR\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.3"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "HardwareNetworkError"
              annotations = {
                description = "Network error(s) detected. Check `ceph health detail`."
                summary     = "Network error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_NETWORK\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.4"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "HardwarePowerError"
              annotations = {
                description = "Power supply error(s) detected. Check `ceph health detail`."
                summary     = "Power supply error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_POWER\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.5"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "HardwareFanError"
              annotations = {
                description = "Fan error(s) detected. Check `ceph health detail`."
                summary     = "Fan error(s) detected"
              }
              expr = "ceph_health_detail{name=\"HARDWARE_FANS\"} > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.13.6"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "PrometheusServer"
          rules = [
            {
              alert = "PrometheusJobMissing"
              annotations = {
                description = "The prometheus job that scrapes from Ceph MGR is no longer defined, this will effectively mean you'll have no metrics or alerts for the cluster.  Please review the job definitions in the prometheus.yml file of the prometheus instance."
                summary     = "The scrape job for Ceph MGR is missing from Prometheus"
              }
              expr = "absent(up{job=\"rook-ceph-mgr\"})"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.12.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "PrometheusJobExporterMissing"
              annotations = {
                description = "The prometheus job that scrapes from Ceph Exporter is no longer defined, this will effectively mean you'll have no metrics or alerts for the cluster.  Please review the job definitions in the prometheus.yml file of the prometheus instance."
                summary     = "The scrape job for Ceph Exporter is missing from Prometheus"
              }
              expr = "sum(absent(up{job=\"rook-ceph-exporter\"})) and sum(ceph_osd_metadata{ceph_version=~\"^ceph version (1[89]|[2-9][0-9]).*\"}) > 0"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.12.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "rados"
          rules = [
            {
              alert = "CephObjectMissing"
              annotations = {
                description   = "The latest version of a RADOS object can not be found, even though all OSDs are up. I/O requests for this object from clients will block (hang). Resolving this issue may require the object to be rolled back to a prior version manually, and manually verified."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks#object-unfound"
                summary       = "Object(s) marked UNFOUND"
              }
              expr = "(ceph_health_detail{name=\"OBJECT_UNFOUND\"} == 1) * on() (count(ceph_osd_up == 1) == bool count(ceph_osd_metadata)) == 1"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.10.1"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "generic"
          rules = [
            {
              alert = "CephDaemonCrash"
              annotations = {
                description   = "One or more daemons have crashed recently, and need to be acknowledged. This notification ensures that software crashes do not go unseen. To acknowledge a crash, use the 'ceph crash archive <id>' command."
                documentation = "https://docs.ceph.com/en/latest/rados/operations/health-checks/#recent-crash"
                summary       = "One or more Ceph daemons have crashed, and are pending acknowledgement"
              }
              expr = "ceph_health_detail{name=\"RECENT_CRASH\"} == 1"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.1.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "rbdmirror"
          rules = [
            {
              alert = "CephRBDMirrorImagesPerDaemonHigh"
              annotations = {
                description = "Number of image replications per daemon is not supposed to go beyond threshold 100"
                summary     = "Number of image replications are now above 100"
              }
              expr = "sum by (ceph_daemon, namespace) (ceph_rbd_mirror_snapshot_image_snapshots) > 100"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.10.2"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephRBDMirrorImagesNotInSync"
              annotations = {
                description = "Both local and remote RBD mirror images should be in sync."
                summary     = "Some of the RBD mirror images are not in sync with the remote counter parts."
              }
              expr = "sum by (ceph_daemon, image, namespace, pool) (topk by (ceph_daemon, image, namespace, pool) (1, ceph_rbd_mirror_snapshot_image_local_timestamp) - topk by (ceph_daemon, image, namespace, pool) (1, ceph_rbd_mirror_snapshot_image_remote_timestamp)) != 0"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.10.3"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephRBDMirrorImagesNotInSyncVeryHigh"
              annotations = {
                description = "More than 10% of the images have synchronization problems"
                summary     = "Number of unsynchronized images are very high."
              }
              expr = "count by (ceph_daemon) ((topk by (ceph_daemon, image, namespace, pool) (1, ceph_rbd_mirror_snapshot_image_local_timestamp) - topk by (ceph_daemon, image, namespace, pool) (1, ceph_rbd_mirror_snapshot_image_remote_timestamp)) != 0) > (sum by (ceph_daemon) (ceph_rbd_mirror_snapshot_snapshots)*.1)"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.10.4"
                severity = "critical"
                type     = "ceph_default"
              }
            },
            {
              alert = "CephRBDMirrorImageTransferBandwidthHigh"
              annotations = {
                description = "Detected a heavy increase in bandwidth for rbd replications (over 80%) in the last 30 min. This might not be a problem, but it is good to review the number of images being replicated simultaneously"
                summary     = "The replication network usage has been increased over 80% in the last 30 minutes. Review the number of images being replicated. This alert will be cleaned automatically after 30 minutes"
              }
              expr = "rate(ceph_rbd_mirror_journal_replay_bytes[30m]) > 0.80"
              for  = "1m"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.10.5"
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
        {
          name = "nvmeof"
          rules = [
            {
              alert = "NVMeoFSubsystemNamespaceLimit"
              annotations = {
                description = "Subsystems have a max namespace limit defined at creation time. This alert means that no more namespaces can be added to {{ $labels.nqn }}"
                summary     = "{{ $labels.nqn }} subsystem has reached its maximum number of namespaces "
              }
              expr = "(count by(nqn) (ceph_nvmeof_subsystem_namespace_metadata)) >= ceph_nvmeof_subsystem_namespace_limit"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFTooManyGateways"
              annotations = {
                description = "You may create many gateways, but 4 is the tested limit"
                summary     = "Max supported gateways exceeded "
              }
              expr = "count(ceph_nvmeof_gateway_info) > 4.00"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFMaxGatewayGroupSize"
              annotations = {
                description = "You may create many gateways in a gateway group, but 2 is the tested limit"
                summary     = "Max gateways within a gateway group ({{ $labels.group }}) exceeded "
              }
              expr = "count by(group) (ceph_nvmeof_gateway_info) > 2.00"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFSingleGatewayGroup"
              annotations = {
                description = "Although a single member gateway group is valid, it should only be used for test purposes"
                summary     = "The gateway group {{ $labels.group }} consists of a single gateway - HA is not possible "
              }
              expr = "count by(group) (ceph_nvmeof_gateway_info) == 1"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFHighGatewayCPU"
              annotations = {
                description = "Typically, high CPU may indicate degraded performance. Consider increasing the number of reactor cores"
                summary     = "CPU used by {{ $labels.instance }} NVMe-oF Gateway is high "
              }
              expr = "label_replace(avg by(instance) (rate(ceph_nvmeof_reactor_seconds_total{mode=\"busy\"}[1m])),\"instance\",\"$1\",\"instance\",\"(.*):.*\") > 80.00"
              for  = "10m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFGatewayOpenSecurity"
              annotations = {
                description = "It is good practice to ensure subsystems use host security to reduce the risk of unexpected data loss"
                summary     = "Subsystem {{ $labels.nqn }} has been defined without host level security "
              }
              expr = "ceph_nvmeof_subsystem_metadata{allow_any_host=\"yes\"}"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFTooManySubsystems"
              annotations = {
                description = "Although you may continue to create subsystems in {{ $labels.gateway_host }}, the configuration may not be supported"
                summary     = "The number of subsystems defined to the gateway exceeds supported values "
              }
              expr = "count by(gateway_host) (label_replace(ceph_nvmeof_subsystem_metadata,\"gateway_host\",\"$1\",\"instance\",\"(.*):.*\")) > 16.00"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFVersionMismatch"
              annotations = {
                description = "This may indicate an issue with deployment. Check cephadm logs"
                summary     = "The cluster has different NVMe-oF gateway releases active "
              }
              expr = "count(count by(version) (ceph_nvmeof_gateway_info)) > 1"
              for  = "1h"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFHighClientCount"
              annotations = {
                description = "The supported limit for clients connecting to a subsystem is 32"
                summary     = "The number of clients connected to {{ $labels.nqn }} is too high "
              }
              expr = "ceph_nvmeof_subsystem_host_count > 32.00"
              for  = "1m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFHighHostCPU"
              annotations = {
                description = "High CPU on a gateway host can lead to CPU contention and performance degradation"
                summary     = "The CPU is high ({{ $value }}%) on NVMeoF Gateway host ({{ $labels.host }}) "
              }
              expr = "100-((100*(avg by(host) (label_replace(rate(node_cpu_seconds_total{mode=\"idle\"}[5m]),\"host\",\"$1\",\"instance\",\"(.*):.*\")) * on(host) group_right label_replace(ceph_nvmeof_gateway_info,\"host\",\"$1\",\"instance\",\"(.*):.*\")))) >= 80.00"
              for  = "10m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFInterfaceDown"
              annotations = {
                description = "A NIC used by one or more subsystems is in a down state"
                summary     = "Network interface {{ $labels.device }} is down "
              }
              expr = "ceph_nvmeof_subsystem_listener_iface_info{operstate=\"down\"}"
              for  = "30s"
              labels = {
                oid      = "1.3.6.1.4.1.50495.1.2.1.14.1"
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFInterfaceDuplex"
              annotations = {
                description = "Until this is resolved, performance from the gateway will be degraded"
                summary     = "Network interface {{ $labels.device }} is not running in full duplex mode "
              }
              expr = "ceph_nvmeof_subsystem_listener_iface_info{duplex!=\"full\"}"
              for  = "30s"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFHighReadLatency"
              annotations = {
                description = "High latencies may indicate a constraint within the cluster e.g. CPU, network. Please investigate"
                summary     = "The average read latency over the last 5 mins has reached 10 ms or more on {{ $labels.gateway }}"
              }
              expr = "label_replace((avg by(instance) ((rate(ceph_nvmeof_bdev_read_seconds_total[1m]) / rate(ceph_nvmeof_bdev_reads_completed_total[1m])))),\"gateway\",\"$1\",\"instance\",\"(.*):.*\") > 0.01"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
            {
              alert = "NVMeoFHighWriteLatency"
              annotations = {
                description = "High latencies may indicate a constraint within the cluster e.g. CPU, network. Please investigate"
                summary     = "The average write latency over the last 5 mins has reached 20 ms or more on {{ $labels.gateway }}"
              }
              expr = "label_replace((avg by(instance) ((rate(ceph_nvmeof_bdev_write_seconds_total[5m]) / rate(ceph_nvmeof_bdev_writes_completed_total[5m])))),\"gateway\",\"$1\",\"instance\",\"(.*):.*\") > 0.02"
              for  = "5m"
              labels = {
                severity = "warning"
                type     = "ceph_default"
              }
            },
          ]
        },
      ]
    }
  }
}
