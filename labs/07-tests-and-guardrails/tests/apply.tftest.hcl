# Integration test: really creates the resources on floci, asserts on what
# came back, then destroys them. name_prefix keeps the test copy apart from
# anything you applied by hand.

variables {
  name_prefix = "lab07-test"
}

run "creates_real_resources" {
  command = apply

  assert {
    condition     = aws_s3_bucket.data.arn == "arn:aws:s3:::lab07-test-data"
    error_message = "Unexpected bucket ARN: ${aws_s3_bucket.data.arn}"
  }

  assert {
    condition     = length(output.canary_version_id) > 0
    error_message = "Canary object has no version ID."
  }

  assert {
    condition     = endswith(output.policy_arn, ":policy/lab07-test-reader")
    error_message = "Unexpected policy ARN: ${output.policy_arn}"
  }

  assert {
    condition     = startswith(output.security_group_id, "sg-")
    error_message = "Security group was not created."
  }
}
