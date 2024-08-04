output "namespace" {
  value = kubernetes_namespace.pihole.metadata[0].name
}

output "pihole_notes" {
  value = helm_release.pihole.metadata[0].notes
}

output "dns_notes" {
  value = helm_release.externaldns_pihole.metadata[0].notes
}
