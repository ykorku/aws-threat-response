data "archive_file" "isolation_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/isolate_instance.py"
  output_path = "${path.module}/build/isolate_instance.zip"
}

resource "aws_lambda_function" "isolate_instance" {
  function_name    = "${var.project_name}-isolate-instance"
  filename         = data.archive_file.isolation_lambda.output_path
  source_code_hash = data.archive_file.isolation_lambda.output_base64sha256
  handler          = "isolate_instance.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  role             = aws_iam_role.lambda_isolation.arn

  environment {
    variables = {
      QUARANTINE_SG_ID = aws_security_group.quarantine.id
      SNS_TOPIC_ARN    = aws_sns_topic.alerts.arn
    }
  }
}
