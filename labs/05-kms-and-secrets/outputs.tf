output "key_arn" {
  description = "ARN of the secrets key."
  value       = aws_kms_key.secrets.arn
}

output "key_alias" {
  description = "Alias of the secrets key."
  value       = aws_kms_alias.secrets.name
}

output "plain_secret_name" {
  value = aws_secretsmanager_secret.plain.name
}

output "wo_secret_name" {
  value = aws_secretsmanager_secret.wo.name
}

# sensitive = true redacts the value in CLI output. It does not keep it out
# of state.
output "plain_password" {
  description = "The state-stored password."
  value       = random_password.plain.result
  sensitive   = true
}
