variable "prometheus_service_account" {
  type        = string
  description = "Service account for prometheus"
}

variable "prometheus_namespace" {
  type        = string
  description = "The namespace for prometheus"
}

variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}
