variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}

variable "prometheus_namespace" {
  type        = string
  description = "The namespace to deploy prometheus rules into"
}

variable "storage_class" {
  type        = string
  description = "The storage class to use for the persistent volume claim"
}

variable "ip_pool" {
  type        = string
  description = "The IP pool to use"
}
