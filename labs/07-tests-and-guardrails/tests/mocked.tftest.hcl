# Offline tests: mock_provider replaces the AWS provider, so no API is called
# and the emulator can be stopped. Computed attributes get generated values
# (a random 8-character string, 0, false, or an empty collection) unless a
# mock_resource, mock_data, or override block supplies them.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"ReadData\",\"Effect\":\"Allow\",\"Action\":[\"s3:GetObject\"],\"Resource\":\"*\"}]}"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "000000000000"
    }
  }

  mock_resource "aws_s3_object" {
    defaults = {
      version_id = "mock-version-1"
    }
  }
}

run "applies_offline" {
  assert {
    condition     = aws_s3_bucket.data.bucket == "lab07-data"
    error_message = "Unexpected bucket name: ${aws_s3_bucket.data.bucket}"
  }

  assert {
    condition     = output.canary_version_id == "mock-version-1"
    error_message = "canary_version_id must come from the canary object."
  }

  assert {
    condition     = aws_s3_object.canary.server_side_encryption == "aws:kms"
    error_message = "Canary object must ask for aws:kms."
  }
}
