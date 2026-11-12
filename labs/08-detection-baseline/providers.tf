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
#
# This is the DEFAULT provider configuration: it has no alias, so every
# resource that does not name a provider uses it.
provider "aws" {
  region     = "us-east-1"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  # One entry per AWS service the lab uses. A service without an entry is
  # sent to real AWS (unless AWS_ENDPOINT_URL is set in your shell) and fails
  # with the fake credentials.
  endpoints {
    cloudtrail = var.floci_endpoint
    events     = var.floci_endpoint
    logs       = var.floci_endpoint
    s3         = var.floci_endpoint
    sns        = var.floci_endpoint
    sts        = var.floci_endpoint
  }
}

# A second configuration of the same provider, selected by alias. Resources
# opt in with "provider = aws.west".
provider "aws" {
  alias      = "west"
  region     = "us-west-2"
  access_key = "test"
  secret_key = "test"

  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  s3_use_path_style           = true

  endpoints {
    cloudtrail = var.floci_endpoint
    events     = var.floci_endpoint
    logs       = var.floci_endpoint
    s3         = var.floci_endpoint
    sns        = var.floci_endpoint
    sts        = var.floci_endpoint
  }
}
