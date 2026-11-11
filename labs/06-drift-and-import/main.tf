# The managed baseline. Step 1 changes all three behind Terraform's back.

locals {
  tags = {
    Lab       = "06-drift-and-import"
    ManagedBy = "terraform"
  }
}

# --- S3: a bucket that must stay private -----------------------------------

resource "aws_s3_bucket" "data" {
  bucket = "lab06-data"
  tags   = local.tags
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket = aws_s3_bucket.data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- EC2: a security group with exactly one ingress rule -------------------

data "aws_vpc" "default" {
  default = true
}

# The rules are written inline on purpose. With inline rules Terraform owns
# the whole rule set, so a rule added out of band shows up as drift. Rules
# managed as separate aws_vpc_security_group_ingress_rule resources do not
# notice extra rules that someone else adds.
resource "aws_security_group" "app" {
  name        = "lab06-app"
  description = "Lab 06 application tier"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTPS from inside the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["172.31.0.0/16"]
  }

  tags = local.tags
}

# --- IAM: a role that only EC2 can assume ----------------------------------

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "lab06-app"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = local.tags
}
