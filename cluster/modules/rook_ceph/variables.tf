variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}

variable "internal_ingress_class" {
  type        = string
  description = "The internal ingress class to use for the dashboard"
}

variable "external_ingress_class" {
  type        = string
  description = "The external ingress class to use for the dashboard"
}

variable "cluster_issuer" {
  type        = string
  description = "The cluster issuer to use for SSL certs"
}
