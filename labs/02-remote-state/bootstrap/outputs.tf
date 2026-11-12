output "state_bucket" {
  description = "Name of the bucket that holds Terraform state."
  value       = aws_s3_bucket.state.id
}

output "kms_key_arn" {
  description = "ARN of the key that encrypts state objects. Passed to the S3 backend at init time."
  value       = aws_kms_key.state.arn
}
