data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  name       = "lab05"
  account_id = data.aws_caller_identity.current.account_id
  root_arn   = "arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"
}

# Two roles to name in the key policy. They only exist so the policy can
# point at real principals; nothing assumes them in this lab.
data "aws_iam_policy_document" "assume_from_account" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.root_arn]
    }
  }
}

resource "aws_iam_role" "key_admin" {
  name               = "${local.name}-key-admin"
  assume_role_policy = data.aws_iam_policy_document.assume_from_account.json
}

resource "aws_iam_role" "key_user" {
  name               = "${local.name}-key-user"
  assume_role_policy = data.aws_iam_policy_document.assume_from_account.json
}

# Key policy: the administrators can manage the key but not use it to
# decrypt; the users can use the key but not manage it. The account root
# statement keeps IAM policies able to grant access and prevents a lockout.
data "aws_iam_policy_document" "key" {
  statement {
    sid       = "EnableIamPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [local.root_arn]
    }
  }

  statement {
    sid = "KeyAdministrators"
    actions = [
      "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*",
      "kms:Update*", "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*",
      "kms:TagResource", "kms:UntagResource", "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.key_admin.arn]
    }
  }

  statement {
    sid       = "KeyUsers"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.key_user.arn]
    }
  }
}

resource "aws_kms_key" "secrets" {
  description             = "lab05 secrets key"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.key.json
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.name}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}
