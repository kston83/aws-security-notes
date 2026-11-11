locals {
  trail_name  = "lab08-trail"
  bucket_name = "lab08-trail-logs"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# --- Log bucket and the policy that lets CloudTrail write to it ------------

resource "aws_s3_bucket" "trail" {
  bucket        = local.bucket_name
  force_destroy = true
}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid       = "AWSCloudTrailAclCheck"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }

  statement {
    sid       = "AWSCloudTrailWrite"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

# --- The trail --------------------------------------------------------------

resource "aws_cloudtrail" "main" {
  name                          = local.trail_name
  s3_bucket_name                = aws_s3_bucket.trail.id
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true

  # The bucket policy must exist before CloudTrail validates the bucket.
  depends_on = [aws_s3_bucket_policy.trail]
}

# --- Alerting: EventBridge rule to an SNS topic -----------------------------

resource "aws_sns_topic" "security_alerts" {
  name = "lab08-security-alerts"
}

resource "aws_cloudwatch_event_rule" "trail_tampering" {
  name        = "lab08-trail-tampering"
  description = "Calls that stop, delete, or loosen the audit trail"

  event_pattern = jsonencode({
    source        = ["aws.cloudtrail", "aws.s3"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["StopLogging", "DeleteTrail", "PutBucketPolicy"]
    }
  })
}

resource "aws_cloudwatch_event_target" "alert" {
  rule = aws_cloudwatch_event_rule.trail_tampering.name
  arn  = aws_sns_topic.security_alerts.arn
}

# --- Metric filter on a log group -------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  name              = "lab08-trail-events"
  retention_in_days = 365
}

resource "aws_cloudwatch_log_metric_filter" "root_usage" {
  name           = "lab08-root-account-usage"
  log_group_name = aws_cloudwatch_log_group.trail.name
  pattern        = "{ $.userIdentity.type = \"Root\" && $.eventType != \"AwsServiceEvent\" }"

  metric_transformation {
    name      = "RootAccountUsage"
    namespace = "Lab08"
    value     = "1"
  }
}

# --- Second Region through the aliased provider ----------------------------

# Without the provider argument this would go to us-east-1.
resource "aws_sns_topic" "west_alerts" {
  provider = aws.west
  name     = "lab08-west-alerts"
}

# The module's own provider "aws" is the caller's aws.west.
module "west_topic" {
  source = "./modules/regional-topic"

  providers = {
    aws = aws.west
  }

  name = "lab08-module-west"
}
