output "block_storage_class" {
  value = helm_release.rook_ceph_cluster.values == null ? yamldecode(file("${path.module}/values/rook-ceph-cluster.values.yaml")).cephBlockPools[0].storageClass.name : merge([for val in helm_release.rook_ceph_cluster.values : yamldecode(val)]...).cephBlockPools[0].storageClass.name
}

output "fs_storage_class" {
  value = helm_release.rook_ceph_cluster.values == null ? yamldecode(file("${path.module}/values/rook-ceph-cluster.values.yaml")).cephFileSystems[0].storageClass.name : merge([for val in helm_release.rook_ceph_cluster.values : yamldecode(val)]...).cephFileSystems[0].storageClass.name
}

output "namespace" {
  value = kubernetes_namespace.rook_ceph.metadata[0].name
}

output "operator_notes" {
  value = helm_release.rook_ceph.metadata[0].notes
}

output "cluster_notes" {
  value = helm_release.rook_ceph_cluster.metadata[0].notes
}
