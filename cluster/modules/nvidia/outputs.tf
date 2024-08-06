output "notes" {
  value = helm_release.nvidia_device_plugin.metadata[0].notes
}
