variable "name" {
  description = "Bucket name. Must carry the lab prefix."
  type        = string

  validation {
    condition     = startswith(var.name, "lab03-")
    error_message = "Bucket name must start with \"lab03-\"."
  }

  validation {
    condition     = can(regex("^[a-z0-9-]{3,63}$", var.name))
    error_message = "Bucket name must be 3-63 characters of lowercase letters, digits, and hyphens."
  }
}

variable "classification" {
  description = "Data classification of the bucket contents."
  type        = string

  validation {
    condition     = contains(["public", "internal", "restricted"], var.classification)
    error_message = "classification must be one of: public, internal, restricted."
  }
}

variable "versioning" {
  description = "Keep previous object versions."
  type        = bool
  default     = true
}

variable "enforce_tls" {
  description = "Attach a bucket policy that denies requests made without TLS."
  type        = bool
  default     = true
}

variable "encryption" {
  description = "Default encryption for new objects."
  type = object({
    algorithm  = optional(string, "AES256")
    bucket_key = optional(bool, false)
  })
  default = {}

  validation {
    condition     = contains(["AES256", "aws:kms", "aws:kms:dsse"], var.encryption.algorithm)
    error_message = "encryption.algorithm must be AES256, aws:kms, or aws:kms:dsse."
  }
}

variable "tags" {
  description = "Tags for the bucket. The module adds Classification."
  type        = map(string)
  default     = {}
}
