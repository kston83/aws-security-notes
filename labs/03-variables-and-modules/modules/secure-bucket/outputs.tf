output "name" {
  description = "Bucket name."
  value       = aws_s3_bucket.this.id
}

output "arn" {
  description = "Bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "tls_enforced" {
  description = "True when the TLS-only bucket policy is attached."
  value       = length(aws_s3_bucket_policy.this) == 1
}
