# Negative tests: each run feeds the configuration something insecure and
# passes only if the named guardrail rejects it.

run "rejects_sse_s3" {
  command = plan

  variables {
    sse_algorithm = "AES256"
  }

  expect_failures = [var.sse_algorithm]
}

run "rejects_ssh_from_anywhere" {
  command = plan

  variables {
    ssh_ingress_cidrs = ["10.7.0.0/16", "0.0.0.0/0"]
  }

  expect_failures = [var.ssh_ingress_cidrs]
}

run "rejects_admin_policy" {
  command = plan

  variables {
    policy_actions   = ["*"]
    policy_resources = ["*"]
  }

  expect_failures = [aws_iam_policy.reader]
}

run "warns_on_wide_ssh_range" {
  command = plan

  variables {
    ssh_ingress_cidrs = ["10.0.0.0/8"]
  }

  expect_failures = [check.ssh_ranges_are_narrow]
}
