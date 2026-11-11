output "bucket_arns" {
  description = "ARN of every bucket, keyed like var.buckets."
  value       = { for key, mod in module.bucket : key => mod.arn }
}

output "restricted_buckets" {
  description = "Names of the buckets classified restricted."
  value       = sort([for key, cfg in var.buckets : module.bucket[key].name if cfg.classification == "restricted"])
}

output "tls_enforced" {
  description = "Whether each bucket carries the TLS-only policy."
  value       = { for key, mod in module.bucket : key => mod.tls_enforced }
}
