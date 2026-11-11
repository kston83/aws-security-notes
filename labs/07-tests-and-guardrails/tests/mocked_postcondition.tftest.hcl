# Offline negative test: override_resource pins the values of one resource, so
# the test can simulate S3 answering in a way that is hard to produce on demand.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }
}

run "postcondition_catches_unversioned_object" {
  # Pretend S3 stored the canary without a version ID.
  override_resource {
    target = aws_s3_object.canary
    values = {
      version_id = "null"
    }
  }

  expect_failures = [aws_s3_object.canary]
}
