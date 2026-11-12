output "bucket_name" {
  value = aws_s3_bucket.data.id
}

output "canary_version_id" {
  description = "Version ID S3 assigned to the canary object."
  value       = aws_s3_object.canary.version_id
}

output "policy_arn" {
  value = aws_iam_policy.reader.arn
}

output "security_group_id" {
  value = aws_security_group.admin.id
}
