# Declares which provider this module needs. It does not configure one: the
# caller decides which configuration the module receives.
terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

variable "name" {
  description = "Name of the SNS topic."
  type        = string
}

resource "aws_sns_topic" "this" {
  name = var.name
}

output "arn" {
  description = "ARN of the topic."
  value       = aws_sns_topic.this.arn
}
