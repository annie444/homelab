resource "helm_release" "nvidia_device_plugin" {
  name       = "nvidia-device-plugin"
  namespace  = "nvidia-device-plugin"
  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = "0.16.1"

  values = [
    file("${path.module}/values/nvidia-device-plugin.values.yaml"),
  ]

  devel            = true
  create_namespace = true
  cleanup_on_fail  = true
  lint             = false
  max_history      = 10
}
