data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = data.aws_availability_zones.available.names[0]

  tags = { Name = "${var.project_name}-public-subnet" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${var.project_name}-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security group for the test instance. SSH is intentionally open to
# 0.0.0.0/0 so GuardDuty has something realistic to evaluate during
# testing — this is the "victim" instance, not a real workload. Never
# do this in a production environment.
resource "aws_security_group" "normal" {
  name        = "${var.project_name}-normal-sg"
  description = "Default security group for the test instance"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from anywhere (test instance only)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-normal-sg" }
}

# Quarantine security group: no ingress, no egress. The Lambda function
# swaps a compromised instance into this group to cut off all network
# access while preserving the instance itself for forensic snapshotting.
resource "aws_security_group" "quarantine" {
  name        = "${var.project_name}-quarantine-sg"
  description = "No ingress or egress rules — used to isolate a compromised instance"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project_name}-quarantine-sg" }
}
