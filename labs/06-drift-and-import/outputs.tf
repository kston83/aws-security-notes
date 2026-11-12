output "bucket_name" {
  description = "Name of the managed bucket."
  value       = aws_s3_bucket.data.bucket
}

output "security_group_id" {
  description = "ID of the managed security group. Step 1 needs it."
  value       = aws_security_group.app.id
}

output "role_arn" {
  description = "ARN of the managed role."
  value       = aws_iam_role.app.arn
}
