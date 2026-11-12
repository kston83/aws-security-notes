# Plan-only tests: nothing is created. Each assert reads planned values.

run "secure_defaults" {
  command = plan

  assert {
    condition     = one(aws_s3_bucket_server_side_encryption_configuration.data.rule).apply_server_side_encryption_by_default[0].sse_algorithm == "aws:kms"
    error_message = "Default encryption must be aws:kms."
  }

  assert {
    condition     = aws_s3_bucket_versioning.data.versioning_configuration[0].status == "Enabled"
    error_message = "Bucket must have versioning enabled."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.data.block_public_acls,
      aws_s3_bucket_public_access_block.data.block_public_policy,
      aws_s3_bucket_public_access_block.data.ignore_public_acls,
      aws_s3_bucket_public_access_block.data.restrict_public_buckets,
    ])
    error_message = "All four public access block settings must be on."
  }

  assert {
    condition     = alltrue([for rule in aws_vpc_security_group_ingress_rule.ssh : rule.cidr_ipv4 != "0.0.0.0/0"])
    error_message = "No ingress from 0.0.0.0/0 on port 22."
  }

  assert {
    condition = alltrue([
      for statement in jsondecode(data.aws_iam_policy_document.reader.json).Statement :
      !contains(flatten([statement.Action]), "*")
    ])
    error_message = "Reader policy must not allow Action \"*\"."
  }
}

run "one_rule_per_range" {
  command = plan

  variables {
    ssh_ingress_cidrs = ["10.7.0.0/16", "192.168.10.0/24"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.ssh) == 2
    error_message = "Expected one SSH ingress rule per CIDR range."
  }
}
