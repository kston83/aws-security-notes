variable "secret_version" {
  description = "Bump this number to make Terraform write a new value through the write-only argument."
  type        = number
  default     = 1
}
