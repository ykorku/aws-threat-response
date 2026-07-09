# GuardDuty automatically sends every finding to the account's default
# EventBridge bus — no extra GuardDuty-side configuration is needed.
# This rule just listens for that event and forwards it to the Lambda.
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${var.project_name}-guardduty-findings"
  description = "Routes GuardDuty findings to the isolation Lambda"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "invoke_lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "isolate-instance-lambda"
  arn       = aws_lambda_function.isolate_instance.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.isolate_instance.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_findings.arn
}
