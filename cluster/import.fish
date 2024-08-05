#!/usr/bin/env fish




function helper
  echo "Usage: $(status filename) <command>"
  echo ""
  echo "Commands:            | Description:"
  echo "---------------------|--------------------------------------------------"
  echo "  all                |   Import all resources"
  echo "  element            |   Import resources for Element"
  echo "  ingress-all        |   Import resources for all Ingresses"
  echo "  internal-ingress   |   Import resources for the internal Ingress"
  echo "  external-ingress   |   Import resources for the external Ingress"
  echo "  cert-manager       |   Import resources for cert-manager"
  echo "  matrix-full        |   Import resources for the full Matrix stack"
  echo "  matrix-media       |   Import resources for the Matrix media repo"
  echo "  synapse            |   Import resources for Matrix Synapse"
  echo "  matrix-monitoring  |   Import resources for Matrix monitoring"
  echo "  metallb            |   Import resources for MetalLB"
  echo "  prometheus         |   Import resources for the Kube Prometheus Stack"
  echo "  monitoring         |   Import resources for the full monitoring stack"
  echo "  grafana            |   Import resources for Grafana"
  echo "  alloy              |   Import resources for Alloy"
  echo "  loki               |   Import resources for Loki"
  echo "  pihole-all         |   Import resources for the full Pi-hole stack"
  echo "  pihole             |   Import resources for Pi-hole"
  echo "  external-dns       |   Import resources for ExternalDNS"
  echo "  postgresql         |   Import resources for PostgreSQL"
  echo "  redis              |   Import resources for Redis"
  echo "  ceph-all           |   Import resources for the full Ceph stack"
  echo "  ceph               |   Import resources for Rook Ceph Operator"
  echo "  ceph-cluster       |   Import resources for the Ceph cluster"
  echo "  ceph-dashboard     |   Import resources for the Ceph dashboard"
  echo "  ceph-monitoring    |   Import resources for Ceph monitoring"
  echo "  eturnal            |   Import resources for Eturnal"
end

function all
  element
  ingress-all
  matrix-full
  metallb
  monitoring
  pihole-all
  postgresql
  redis
  ceph-all
end

function redis
  terraform import module.redis.kubernetes_namespace.redis redis
  terraform import module.redis.helm_release.redis redis/redis
end

function element
  terraform import module.element.kubernetes_namespace.element element
  terraform import module.element.helm_release.element_web element/element-web
end

function ingress-all
  internal-ingress
  external-ingress
  cert-manager
end

function internal-ingress
  terraform import module.ingress.module.default_ingress['"internal"'].kubernetes_namespace.nginx internal-nginx-system
  terraform import module.ingress.module.default_ingress['"internal"'].helm_release.ingress_nginx internal-nginx-system/ingress-nginx-internal
end

function external-ingress
  terraform import module.ingress.module.default_ingress['"external"'].kubernetes_namespace.nginx nginx-system
  terraform import module.ingress.module.default_ingress['"external"'].helm_release.ingress_nginx nginx-system/ingress-nginx
end


function cert-manager
  terraform import module.ingress.kubernetes_namespace.cert_manager cert-manager
  terraform import module.ingress.helm_release.cert_manager cert-manager/cert-manager
  terraform import module.ingress.kubernetes_manifest.cluster_issuer "apiVersion=cert-manager.io/v1,kind=ClusterIssuer,namespace=cert-manager,name=letsencrypt-prod"
end

function matrix-full
  terraform import module.matrix.kubernetes_namespace.matrix matrix
  eturnal
  matrix-media
  synapse
  matrix-monitoring
end


function matrix-media
  terraform import module.matrix.kubernetes_persistent_volume_claim.matrix_media matrix/matrix-media-repo
  terraform import module.matrix.helm_release.matrix_media_repo matrix/matrix-media-repo
end

function synapse
  terraform import module.matrix.kubernetes_persistent_volume_claim.matrix_data matrix/matrix-data
  terraform import module.matrix.helm_release.matrix_synapse matrix/matrix-synapse
end

function matrix-monitoring
  terraform import module.matrix.kubernetes_manifest.matrix_podmonitor "apiVersion=monitoring.coreos.com/v1,kind=PodMonitor,name=matrix-synapse,namespace=matrix"
  terraform import module.matrix.kubernetes_manifest.prometheus_matrix_rules "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,name=prometheus-matrix-rules,namespace=matrix"
end

function metallb
  terraform import module.metallb.kubernetes_namespace.metallb metallb-system
  terraform import module.metallb.resource.helm_release.metallb metallb-system/metallb
  terraform import module.metallb.kubernetes_manifest.ip_pool "apiVersion=metallb.io/v1beta1,kind=IPAddressPool,name=pool,namespace=metallb-system"
  terraform import module.metallb.kubernetes_manifest.ip_advertisement "apiVersion=metallb.io/v1beta1,kind=L2Advertisement,name=pool,namespace=metallb-system"
end

function prometheus
  terraform import module.monitoring.resource.helm_release.prometheus_stack monitoring/prometheus-stack
end

function monitoring
  terraform import module.monitoring.kubernetes_namespace.monitoring monitoring
  prometheus
  grafana
  alloy
  loki
end

function grafana
  terraform import module.monitoring.resource.kubernetes_secret.grafana_admin_credentials monitoring/grafana-admin-credentials
  terraform import module.monitoring.resource.kubernetes_role.grafana monitoring/grafana-secret
  terraform import module.monitoring.kubernetes_role_binding.grafana monitoring/grafana-secrets
  terraform import module.monitoring.kubernetes_ingress_v1.grafana_external monitoring/grafana-external
end

function alloy
  terraform import module.monitoring.resource.helm_release.alloy monitoring/alloy
end

function loki
  terraform import module.monitoring.resource.helm_release.loki monitoring/loki
end

function pihole-all
  pihole
  external-dns
end

function pihole
  terraform import module.pihole.kubernetes_namespace.pihole pihole-system
  terraform import module.pihole.helm_release.pihole pihole-system/pihole
end

function external-dns
  terraform import module.pihole.helm_release.externaldns_pihole pihole-system/externaldns-pihole
end

function postgresql
  terraform import module.postgresql.kubernetes_namespace.postgresql postgresql
  terraform import module.postgresql.kubernetes_secret.postgresql postgresql/postgresql-secret
  terraform import module.postgresql.helm_release.postgresql postgresql/postgresql
end

function ceph-all
  terraform import module.rook_ceph.kubernetes_namespace.rook_ceph rook-ceph
  ceph
  ceph-cluster
  ceph-dashboard
  ceph-monitoring
end

function ceph
  terraform import module.rook_ceph.helm_release.rook_ceph rook-ceph/rook-ceph
end

function ceph-cluster
  terraform import module.rook_ceph.helm_release.rook_ceph_cluster rook-ceph/rook-ceph-cluster
end

function ceph-dashboard
    terraform import module.rook_ceph.kubernetes_service.ceph_dashboard rook-ceph/rook-ceph-mgr-dashboard-external-https
    terraform import module.rook_ceph.kubernetes_ingress_v1.ceph_dashboard rook-ceph/rook-ceph-mgr-dashboard
end

function ceph-monitoring
  terraform import module.rook_ceph.kubernetes_manifest.ceph_prometheus_rules "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,name=prometheus-ceph-external-rules,namespace=rook-ceph"
  terraform import module.rook_ceph.kubernetes_manifest.prometheusrule_rook_ceph_prometheus_ceph_rules "apiVersion=monitoring.coreos.com/v1,kind=PrometheusRule,name=prometheus-ceph-rules,namespace=rook-ceph"
  terraform import module.rook_ceph.kubernetes_manifest.csi_metrics "apiVersion=monitoring.coreos.com/v1,kind=ServiceMonitor,name=csi-metrics,namespace=rook-ceph"
end

function eturnal
  terraform import module.matrix.module.eturnal.kubernetes_deployment.eturnal matrix/eturnal
  terraform import module.matrix.module.eturnal.kubernetes_config_map.udp_services nginx-system/ingress-ngnix-udp-services-configmap
  terraform import module.matrix.module.eturnal.kubernetes_config_map.tcp_services nginx-system/ingress-ngnix-tcp-services-configmap
  terraform import module.matrix.module.eturnal.kubernetes_manifest.eturnal_certificate "apiVersion=cert-manager.io/v1,kind=Certificate,name=turn.jpeg.gay,namespace=matrix"
  terraform import module.matrix.module.eturnal.kubernetes_service.eturnal matrix/eturnal
  terraform import module.matrix.module.eturnal.kubernetes_ingress_v1.eturnal matrix/eturnal
  terraform import module.matrix.module.eturnal.kubernetes_config_map.eturnal_config matrix/eturnal-config
  terraform import module.matrix.module.eturnal.kubernetes_secret.eturnal_secret matrix/eturnal-secret
  terraform import module.matrix.module.eturnal.kubernetes_secret.eturnal_tls matrix/turn.jpeg.gay
  terraform import module.matrix.module.eturnal.kubernetes_config_map.eturnal_env matrix/eturnal-env
end

switch $argv[1]
  case 'all'
    all
    exit 0
  case 'element'
    element
    exit 0
  case 'ingress-all'
    ingress-all
    exit 0
  case 'internal-ingress'
    internal-ingress
    exit 0
  case 'external-ingress'
    external-ingress
    exit 0
  case 'cert-manager'
    cert-manager
    exit 0
  case 'matrix-full'
    matrix-full
    exit 0
  case 'matrix-media'
    matrix-media
    exit 0
  case 'synapse'
    synapse
    exit 0
  case 'matrix-monitoring'
    matrix-monitoring
    exit 0
  case 'metallb'
    metallb
    exit 0
  case 'prometheus'
    prometheus
    exit 0
  case 'monitoring'
    monitoring
    exit 0
  case 'grafana'
    grafana
    exit 0
  case 'alloy'
    alloy
    exit 0
  case 'loki'
    loki
    exit 0
  case 'pihole-all'
    pihole-all
    exit 0
  case 'pihole'
    pihole
    exit 0
  case 'external-dns'
    external-dns
    exit 0
  case 'postgresql'
    postgresql
    exit 0
  case 'redis'
    redis
    exit 0
  case 'ceph-all'
    ceph-all
    exit 0
  case 'ceph'
    ceph
    exit 0
  case 'ceph-cluster'
    ceph-cluster
    exit 0
  case 'ceph-dashboard'
    ceph-dashboard
    exit 0
  case 'ceph-monitoring'
    ceph-monitoring
    exit 0
  case 'eturnal'
    eturnal
    exit 0
  case '*'
    helper
    exit 1
end
