variable "cluster_issuer" {
  type        = string
  description = "The cluster issuer to use for the ingress controller"
}

variable "ingress_class" {
  type        = string
  description = "The ingress class to use for the ingress controller"
}
