variable "name_prefix" {
  description = "Prefix for every resource name. Tests override it so they do not collide with an applied copy."
  type        = string
  default     = "lab07"

  validation {
    condition     = startswith(var.name_prefix, "lab07")
    error_message = "name_prefix must start with \"lab07\"."
  }
}

# Guardrail 1: variable validation. Runs first, before Terraform plans anything.
variable "sse_algorithm" {
  description = "Default encryption algorithm for the bucket."
  type        = string
  default     = "aws:kms"

  validation {
    condition     = contains(["aws:kms", "aws:kms:dsse"], var.sse_algorithm)
    error_message = "Encryption algorithm must be aws:kms or aws:kms:dsse. SSE-S3 (AES256) is not allowed."
  }
}

variable "ssh_ingress_cidrs" {
  description = "CIDR ranges allowed to reach port 22 on the admin security group."
  type        = list(string)
  default     = ["10.7.0.0/16"]

  validation {
    condition     = alltrue([for cidr in var.ssh_ingress_cidrs : can(cidrhost(cidr, 0))])
    error_message = "Every entry must be a valid IPv4 CIDR range, such as 10.7.0.0/16."
  }

  validation {
    condition     = !contains(var.ssh_ingress_cidrs, "0.0.0.0/0")
    error_message = "No ingress from 0.0.0.0/0 on port 22."
  }
}

# The next three variables have no validation on purpose. The guardrails that
# cover them live on the resources (main.tf) and in a check block (checks.tf).
variable "versioning_enabled" {
  description = "Keep previous object versions."
  type        = bool
  default     = true
}

variable "policy_actions" {
  description = "Actions the reader policy allows."
  type        = list(string)
  default     = ["s3:GetObject", "s3:ListBucket"]
}

variable "policy_resources" {
  description = "Resources the reader policy applies to. Null means this lab's bucket and its objects."
  type        = list(string)
  default     = null
}

variable "expected_account_id" {
  description = "Account this configuration is meant for. The emulator's account is all zeros."
  type        = string
  default     = "000000000000"
}
