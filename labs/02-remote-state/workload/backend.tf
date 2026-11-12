# Where this configuration keeps its state. A backend block cannot use
# variables or references, so the KMS key ARN (different on every run of the
# lab) is supplied at init time with -backend-config.
terraform {
  backend "s3" {
    bucket       = "lab02-tfstate"
    key          = "workload/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true

    # Lab-only settings, same purpose as in the provider block. The backend
    # does not read the provider block, so they are repeated here.
    access_key                  = "test"
    secret_key                  = "test"
    use_path_style              = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_requesting_account_id  = true

    endpoints = {
      s3 = "http://localhost:4566"
    }
  }
}
