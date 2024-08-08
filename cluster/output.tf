output "notes" {
  value = [module.rook_ceph.operator_notes, module.rook_ceph.cluster_notes, module.cilium.notes, module.pihole.pihole_notes, module.ingress.internal_notes, module.ingress.external_notes, module.pihole.dns_notes, module.ingress.cert_notes, module.monitoring.prometheus_notes, module.monitoring.alloy_notes, module.monitoring.loki_notes, module.postgresql.notes, module.redis.notes, module.element.notes, module.matrix.media_notes, module.matrix.synapse_notes, module.nvidia.notes]
}

output "postgres_host" {
  value = module.postgresql.host
}

output "redis_host" {
  value = module.redis.host
}
