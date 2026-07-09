output "test_instance_id" {
  description = "Use this ID when crafting a manual test event"
  value       = aws_instance.test.id
}

output "quarantine_security_group_id" {
  value = aws_security_group.quarantine.id
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "guardduty_detector_id" {
  description = "Needed for `aws guardduty create-sample-findings`"
  value       = aws_guardduty_detector.main.id
}

output "lambda_function_name" {
  value = aws_lambda_function.isolate_instance.function_name
}
