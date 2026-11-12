# (a) The password is a managed resource, so its value is stored in state.
resource "random_password" "plain" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "plain" {
  name                    = "${local.name}/db-password-plain"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "plain" {
  secret_id     = aws_secretsmanager_secret.plain.id
  secret_string = random_password.plain.result
}

# (b) The password is ephemeral and goes in through a write-only argument.
# Terraform never stores either one. Requires Terraform 1.11+ and AWS
# provider 5.x/6.x with secret_string_wo.
ephemeral "random_password" "wo" {
  length  = 24
  special = false
}

resource "aws_secretsmanager_secret" "wo" {
  name                    = "${local.name}/db-password-wo"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "wo" {
  secret_id                = aws_secretsmanager_secret.wo.id
  secret_string_wo         = ephemeral.random_password.wo.result
  secret_string_wo_version = var.secret_version
}
