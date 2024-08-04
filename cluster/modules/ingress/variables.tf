variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}

variable "ip_pool" {
  type        = string
  description = "The metallb IP pool the ingress controller should bind to"
}
