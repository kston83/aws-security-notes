terraform {
  required_version = ">= 1.12"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "floci_endpoint" {
  description = "Base URL of the floci emulator."
  type        = string
  default     = "http://localhost:4566"
}

# Lab-only provider settings. The fake credentials, the skip_* flags, and the
# endpoints block exist only to point the provider at the emulator. None of
# them belong in a configuration that targets real AWS.
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # One entry per AWS service the lab uses. A service without an entry is
  # sent to real AWS and fails with the fake credentials.
  endpoints {
    s3  = var.floci_endpoint
    sts = var.floci_endpoint
  }
}
