# Guardrail 4: check blocks. Evaluated at the end of every plan and apply.
# A failed check is a warning. It never stops the run.

check "ssh_ranges_are_narrow" {
  assert {
    condition     = alltrue([for cidr in var.ssh_ingress_cidrs : tonumber(split("/", cidr)[1]) >= 16])
    error_message = "An SSH ingress range is wider than /16. Allowed, but confirm it is intended."
  }
}

# A scoped data source exists only inside its check block. This one asks STS
# which account the credentials belong to.
check "expected_account" {
  data "aws_caller_identity" "current" {}

  assert {
    condition     = data.aws_caller_identity.current.account_id == var.expected_account_id
    error_message = "Credentials are for account ${data.aws_caller_identity.current.account_id}, not ${var.expected_account_id}."
  }
}
