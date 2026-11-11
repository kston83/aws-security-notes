# Data sources: read-only lookups. Terraform reads them during plan and
# creates nothing. They let the configuration build ARNs without a
# hard-coded account ID, partition, or Region.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  name       = "lab04-app"
  app_prefix = "app/"

  # An ARN pattern for things this configuration does not manage (the
  # application's SSM parameters), assembled from data sources.
  parameter_arn = "arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/lab04/*"
}

# Managed resources: Terraform creates, updates, and deletes these.
resource "aws_s3_bucket" "data" {
  bucket        = "${local.name}-data"
  force_destroy = true
}

resource "aws_kms_key" "data" {
  description             = "lab04 application data key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "data" {
  name          = "alias/${local.name}-data"
  target_key_id = aws_kms_key.data.key_id
}
