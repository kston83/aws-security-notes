variable "environment" {
  description = "Deployment stage. Becomes part of every bucket name and a tag."
  type        = string
  default     = "sandbox"

  validation {
    condition     = contains(["sandbox", "dev", "test", "prod"], var.environment)
    error_message = "environment must be one of: sandbox, dev, test, prod."
  }
}

variable "owner" {
  description = "Team that owns the buckets. Used as a tag."
  type        = string
  default     = "unassigned"
}

variable "extra_tags" {
  description = "Tags merged over the common tags."
  type        = map(string)
  default     = {}
}

# map(object) with optional() attributes: each bucket must state its
# classification; everything else falls back to a secure default.
variable "buckets" {
  description = "Buckets to create, keyed by a short purpose name."
  type = map(object({
    classification = string
    versioning     = optional(bool, true)
    enforce_tls    = optional(bool, true)
    encryption = optional(object({
      algorithm  = optional(string, "AES256")
      bucket_key = optional(bool, false)
    }), {})
  }))
}
