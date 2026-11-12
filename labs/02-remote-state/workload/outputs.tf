output "parameter_name" {
  description = "Name of the SSM parameter that holds the password."
  value       = aws_ssm_parameter.db_password.name
}

output "db_password" {
  description = "The generated password. Marked sensitive, which hides it from CLI output only."
  value       = random_password.db.result
  sensitive   = true
}
