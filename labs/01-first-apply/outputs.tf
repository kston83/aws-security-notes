output "bucket_name" {
  description = "Name of the hardened bucket."
  value       = aws_s3_bucket.this.id
}

output "kms_key_id" {
  description = "ID of the key that encrypts new objects in the bucket."
  value       = aws_kms_key.bucket.key_id
}
