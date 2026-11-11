# Trust policy: who may assume the role. Only the EC2 service, and only for
# instances in this account.
data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "Ec2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Permissions policy: what the role may do. Every statement names specific
# actions and a specific resource. The references to aws_s3_bucket.data and
# aws_kms_key.data are what make Terraform create those two first.
data "aws_iam_policy_document" "app" {
  statement {
    sid       = "ReadWriteAppPrefix"
    actions   = ["s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.data.arn}/${local.app_prefix}*"]
  }

  statement {
    sid       = "ListAppPrefix"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.data.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.app_prefix}*"]
    }
  }

  statement {
    sid       = "UseDataKey"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [aws_kms_key.data.arn]
  }

  # Attribute-based access control (ABAC): the role may read a parameter
  # only when the parameter's project tag equals the role's own project tag.
  # &{...} is how this data source writes an IAM policy variable, because
  # Terraform would read ${...} as its own interpolation.
  statement {
    sid       = "ReadOwnProjectParameters"
    actions   = ["ssm:GetParameter", "ssm:GetParametersByPath"]
    resources = [local.parameter_arn]

    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/project"
      values   = ["&{aws:PrincipalTag/project}"]
    }
  }
}

# Permissions boundary: the most the role can ever be granted, whatever
# policies are attached later. It grants nothing by itself.
data "aws_iam_policy_document" "boundary" {
  statement {
    sid       = "ServicesTheAppMayUse"
    actions   = ["s3:*", "kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey", "ssm:GetParameter*"]
    resources = ["*"]
  }

  statement {
    sid       = "NeverIamOrKeyAdmin"
    effect    = "Deny"
    actions   = ["iam:*", "kms:ScheduleKeyDeletion", "kms:PutKeyPolicy", "kms:DisableKey"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "boundary" {
  name        = "${local.name}-boundary"
  description = "Permissions boundary for lab04 application roles"
  policy      = data.aws_iam_policy_document.boundary.json
}

resource "aws_iam_policy" "app" {
  name        = "${local.name}-access"
  description = "Least-privilege access to one S3 prefix and one KMS key"
  policy      = data.aws_iam_policy_document.app.json
}

resource "aws_iam_role" "app" {
  name                 = "${local.name}-role"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  permissions_boundary = aws_iam_policy.boundary.arn

  tags = {
    project = "lab04"
  }
}

resource "aws_iam_role_policy_attachment" "app" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.app.arn
}

# The instance profile references only the role, so Terraform would happily
# create it before the policy is attached. Software that starts with this
# profile needs the permissions to be there already. Nothing in the
# arguments expresses that, so depends_on does.
resource "aws_iam_instance_profile" "app" {
  name = "${local.name}-profile"
  role = aws_iam_role.app.name

  depends_on = [aws_iam_role_policy_attachment.app]
}
