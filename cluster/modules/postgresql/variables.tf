variable "storage_class" {
  type        = string
  description = "The storage class to use for the bucket"
}

variable "monitoring" {
  type        = bool
  description = "A string reprisentation of a boolean stating whether prometheus monitoring should be configured"
}
