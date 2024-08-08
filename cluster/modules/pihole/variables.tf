variable "ingress_class" {
  type        = string
  description = "The ingress class to bind to"
}

variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}
