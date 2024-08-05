variable "prefix" {
  type     = string
  default  = null
  nullable = true
}

variable "suffix" {
  type     = string
  default  = null
  nullable = true
}

variable "monitoring" {
  type = bool
}

variable "extra_values" {
  type    = list(string)
  default = []
}

variable "ingress_class" {
  type     = string
  nullable = false
}

variable "ip_pool" {
  type     = string
  nullable = true
}
