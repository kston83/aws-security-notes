variable "bucket_name" {
  description = "Name of the lab bucket. Changing it forces Terraform to replace the bucket."
  type        = string
  default     = "lab01-first-apply"
}

variable "data_classification" {
  description = "Value of the bucket's Classification tag. Changing it updates the bucket in place."
  type        = string
  default     = "internal"
}

locals {
  tags = {
    Lab     = "01-first-apply"
    Managed = "terraform"
  }
}

# Customer managed key for the bucket's default encryption.
resource "aws_kms_key" "bucket" {
  description             = "lab01 key for S3 default encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  tags                    = local.tags
}

resource "aws_kms_alias" "bucket" {
  name          = "alias/lab01-bucket"
  target_key_id = aws_kms_key.bucket.key_id
}

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name
  tags   = merge(local.tags, { Classification = var.data_classification })
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.bucket.arn
    }
  }
}
