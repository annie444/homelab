output "media_notes" {
  value = helm_release.matrix_media_repo.metadata[0].notes
}

output "synapse_notes" {
  value = helm_release.matrix_synapse.metadata[0].notes
}

output "namespace" {
  value = kubernetes_namespace.matrix.metadata[0].name
}
