resource "aws_iam_role" "lambda_isolation" {
  name = "${var.project_name}-lambda-isolation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic_logging" {
  role       = aws_iam_role.lambda_isolation.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Scoped to exactly what the function does: read instance metadata, tag
# it, snapshot its volumes, change its security groups, and publish to
# the one SNS topic it needs. No wildcard "ec2:*" or "*" resource on IAM
# or other services.
resource "aws_iam_role_policy" "lambda_isolation_permissions" {
  name = "${var.project_name}-lambda-isolation-policy"
  role = aws_iam_role.lambda_isolation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAndTagInstances"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:CreateTags"
        ]
        Resource = "*" # DescribeInstances does not support resource-level restriction
      },
      {
        Sid    = "IsolateInstance"
        Effect = "Allow"
        Action = [
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
      },
      {
        Sid    = "ForensicSnapshot"
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot"
        ]
        Resource = "*"
      },
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}
