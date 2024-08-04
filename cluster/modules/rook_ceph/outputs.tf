output "block_storage_class" {
  value = yamldecode(helm_release.rook_ceph_cluster.values[0]).cephBlockPools[0].storageClass.name
}

output "fs_storage_class" {
  value = yamldecode(helm_release.rook_ceph_cluster.values[0]).cephFileSystems[0].storageClass.name
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
