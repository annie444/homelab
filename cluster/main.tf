module "monitoring" {
  source = "./modules/monitoring"
}

module "rook_ceph" {
  source = "./modules/rook_ceph"

  monitoring             = module.monitoring.enabled
  internal_ingress_class = module.ingress.internal_ingress
  external_ingress_class = module.ingress.external_ingress
  cluster_issuer         = module.ingress.cluster_issuer
}

module "pihole" {
  source = "./modules/pihole"

  monitoring    = module.monitoring.enabled
  ingress_class = module.ingress.internal_ingress
  ip_pool       = module.metallb.ip_pool
}

module "ingress" {
  source = "./modules/ingress"

  monitoring = module.monitoring.enabled
  ip_pool    = module.metallb.ip_pool
}

module "redis" {
  source = "./modules/redis"

  monitoring           = module.monitoring.enabled
  ip_pool              = module.metallb.ip_pool
  storage_class        = module.rook_ceph.block_storage_class
  prometheus_namespace = module.monitoring.namespace
}

module "postgresql" {
  source = "./modules/postgresql"

  monitoring    = module.monitoring.enabled
  storage_class = module.rook_ceph.block_storage_class
}

module "matrix" {
  source = "./modules/matrix"

  monitoring        = module.monitoring.enabled
  postgresql_host   = module.postgresql.host
  storage_class     = module.rook_ceph.fs_storage_class
  cluster_issuer    = module.ingress.cluster_issuer
  ingress_class     = module.ingress.external_ingress
  redis_host        = module.redis.host
  ingress_namespace = module.ingress.external_namespace
}

module "nvidia" {
  source = "./modules/nvidia"
}

module "metallb" {
  source = "./modules/metallb"

  prometheus_namespace       = module.monitoring.namespace
  prometheus_service_account = module.monitoring.prometheus_service_account
  monitoring                 = module.monitoring.enabled
}

module "element" {
  source = "./modules/element"

  ingress_class  = module.ingress.external_ingress
  cluster_issuer = module.ingress.cluster_issuer
}
