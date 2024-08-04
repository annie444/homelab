output "rook_ceph_notes" {
  value = module.rook_ceph.operator_notes
}

output "rook_ceph_cluster_notes" {
  value = module.rook_ceph.cluster_notes
}

output "metallb_notes" {
  value = module.metallb.notes
}

output "pihole_notes" {
  value = module.pihole.pihole_notes
}

output "ingress_nginx_internal_notes" {
  value = module.ingress.internal_notes
}

output "ingress_nginx_notes" {
  value = module.ingress.external_notes
}

output "externaldns_pihole_notes" {
  value = module.pihole.dns_notes
}

output "cert_manager_notes" {
  value = module.ingress.cert_notes
}

output "prometheus_stack_notes" {
  value = module.monitoring.prometheus_notes
}

output "alloy_notes" {
  value = module.monitoring.alloy_notes
}

output "loki_notes" {
  value = module.monitoring.loki_notes
}

output "postgresql_notes" {
  value = module.postgresql.notes
}

output "redis_notes" {
  value = module.redis.notes
}

output "element_web_notes" {
  value = module.element.notes
}

output "matrix_media_repo_notes" {
  value = module.matrix.media_notes
}

output "matrix_synapse_notes" {
  value = module.matrix.synapse_notes
}
