locals {
  bucket_name = "${var.name_prefix}-data"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"

  policy_resources = coalesce(var.policy_resources, [local.bucket_arn, "${local.bucket_arn}/*"])
}

resource "aws_s3_bucket" "data" {
  bucket        = local.bucket_name
  force_destroy = true # lab only
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "data" {
  bucket = aws_s3_bucket.data.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = var.sse_algorithm
    }
  }
}

# A canary object. Whether S3 hands back a version ID for it is something only
# the service can say, so it proves versioning is really on.
resource "aws_s3_object" "canary" {
  bucket  = aws_s3_bucket.data.id
  key     = "guardrail-canary.txt"
  content = "written by lab07"

  server_side_encryption = var.sse_algorithm

  depends_on = [aws_s3_bucket_versioning.data]

  lifecycle {
    # Guardrail 3: postcondition. Checks a guarantee about the resource
    # itself. version_id is not known until the object exists, so this one
    # runs during apply, after the object is created.
    postcondition {
      condition     = !contains(["", "null"], coalesce(self.version_id, "null"))
      error_message = "Bucket must have versioning enabled: the canary object came back without a version ID."
    }
  }
}

data "aws_iam_policy_document" "reader" {
  statement {
    sid       = "ReadData"
    actions   = var.policy_actions
    resources = local.policy_resources
  }
}

resource "aws_iam_policy" "reader" {
  name   = "${var.name_prefix}-reader"
  policy = data.aws_iam_policy_document.reader.json

  lifecycle {
    # Guardrail 2: precondition. Checks an assumption before Terraform
    # creates or changes this resource.
    precondition {
      condition     = !(contains(var.policy_actions, "*") && contains(local.policy_resources, "*"))
      error_message = "Policy must not allow Action \"*\" on Resource \"*\"."
    }
  }
}

resource "aws_vpc" "lab" {
  cidr_block = "10.7.0.0/16"

  tags = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_security_group" "admin" {
  name        = "${var.name_prefix}-admin"
  description = "Admin access for lab 07"
  vpc_id      = aws_vpc.lab.id
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.ssh_ingress_cidrs)

  security_group_id = aws_security_group.admin.id
  description       = "SSH from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}
