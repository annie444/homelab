variable "namespace" {
  type = string
}

variable "ingress_namespace" {
  type = string
}

variable "ingress_class" {
  type = string
}

variable "cluster_issuer" {
  type = string
}

variable "eturnal_secret" {
  type      = string
  sensitive = true
}
