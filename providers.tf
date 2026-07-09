terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Local state is fine for a portfolio/learning project. For anything
  # shared with a team, move this to an S3 backend with state locking.
}

provider "aws" {
  region = var.aws_region
}
