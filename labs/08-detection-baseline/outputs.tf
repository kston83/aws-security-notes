output "trail_arn" {
  description = "ARN of the multi-Region trail."
  value       = aws_cloudtrail.main.arn
}

output "alerts_topic_arn" {
  description = "ARN of the security alerts topic (us-east-1)."
  value       = aws_sns_topic.security_alerts.arn
}

output "west_topic_arns" {
  description = "ARNs of the two us-west-2 topics: one direct, one through the module."
  value       = [aws_sns_topic.west_alerts.arn, module.west_topic.arn]
}
