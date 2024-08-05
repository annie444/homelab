variable "storage_class" {
  type        = string
  description = "The storage class of the media bucket"
}

variable "postgresql_host" {
  type        = string
  description = "The hostname of the postgresql pod/svc"
}

variable "redis_host" {
  type        = string
  description = "The hostname of the redis pod/svc"
}

variable "cluster_issuer" {
  type        = string
  description = "The cert manager cluster issuer name"
}

variable "ingress_class" {
  type        = string
  description = "The external ingress class to use"
}

variable "ingress_namespace" {
  type        = string
  description = "The external ingress namespace"
}

variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}
