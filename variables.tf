variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address that receives incident notifications from SNS"
  type        = string
}

variable "project_name" {
  description = "Prefix used to name every resource this project creates"
  type        = string
  default     = "threat-response-demo"
}
