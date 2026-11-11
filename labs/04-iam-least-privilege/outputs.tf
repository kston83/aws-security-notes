output "role_arn" {
  description = "ARN of the application role."
  value       = aws_iam_role.app.arn
}

output "policy_arn" {
  description = "ARN of the customer managed permissions policy."
  value       = aws_iam_policy.app.arn
}

output "boundary_arn" {
  description = "ARN of the permissions boundary policy."
  value       = aws_iam_policy.boundary.arn
}

output "bucket_arn" {
  description = "ARN of the data bucket."
  value       = aws_s3_bucket.data.arn
}

output "key_arn" {
  description = "ARN of the data key."
  value       = aws_kms_key.data.arn
}

output "account_id" {
  description = "Account ID read from data.aws_caller_identity."
  value       = data.aws_caller_identity.current.account_id
}
