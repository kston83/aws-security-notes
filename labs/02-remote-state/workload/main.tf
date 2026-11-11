# A deliberately bad pattern, used here to show what ends up in state:
# Terraform generates a secret, so Terraform has to remember it.

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/lab02/db-password"
  type  = "SecureString"
  value = random_password.db.result

  tags = {
    Lab     = "02-remote-state"
    Managed = "terraform"
  }
}
