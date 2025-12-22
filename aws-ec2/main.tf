# Ladybugs AWS Infrastructure
# Deploys Ladybugs on an EC2 instance with Docker Compose

terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Get latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC
resource "aws_vpc" "ladybugs" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Internet Gateway
resource "aws_internet_gateway" "ladybugs" {
  vpc_id = aws_vpc.ladybugs.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Public Subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.ladybugs.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ladybugs.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ladybugs.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Route Table Association
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Security Group
resource "aws_security_group" "ladybugs" {
  name        = "${var.project_name}-sg"
  description = "Security group for Ladybugs application"
  vpc_id      = aws_vpc.ladybugs.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_ssh_cidrs
  }

  # Ladybugs API (HTTP - API Gateway handles HTTPS externally)
  ingress {
    description = "Ladybugs API"
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  # Neo4j Browser (HTTP)
  ingress {
    description = "Neo4j Browser"
    from_port   = 7474
    to_port     = 7474
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  # Neo4j Bolt
  ingress {
    description = "Neo4j Bolt"
    from_port   = 7687
    to_port     = 7687
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  # Seq Logs UI (HTTP)
  ingress {
    description = "Seq Logs"
    from_port   = 5341
    to_port     = 5341
    protocol    = "tcp"
    cidr_blocks = var.allowed_api_cidrs
  }

  # Outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-sg"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Elastic IP for stable public address
resource "aws_eip" "ladybugs" {
  domain = "vpc"

  tags = {
    Name        = "${var.project_name}-eip"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EIP Association
resource "aws_eip_association" "ladybugs" {
  instance_id   = aws_instance.ladybugs.id
  allocation_id = aws_eip.ladybugs.id
}

# Generate .env content from variables
locals {
  env_content = join("\n", [
    for key, value in var.ladybugs_env_vars : "${key}=${value}"
  ])

  # Determine if we're using Secrets Manager (either existing or created)
  use_secrets_manager = var.secrets_manager_arn != "" || var.create_secrets_manager

  # The ARN to use - either provided or created
  secrets_manager_arn = var.secrets_manager_arn != "" ? var.secrets_manager_arn : (
    var.create_secrets_manager ? aws_secretsmanager_secret.ladybugs[0].arn : ""
  )

  # Secret name for created secrets
  secrets_manager_name = var.secrets_manager_name != "" ? var.secrets_manager_name : "${var.project_name}-${var.environment}-env"
}

# =============================================================================
# Secrets Manager (Optional) - For secure environment variable storage
# =============================================================================

# Create Secrets Manager secret (only when create_secrets_manager is true)
resource "aws_secretsmanager_secret" "ladybugs" {
  count = var.create_secrets_manager ? 1 : 0

  name        = local.secrets_manager_name
  description = "Environment variables for Ladybugs application"

  tags = {
    Name        = "${var.project_name}-secrets"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Store the environment variables as JSON in the secret
resource "aws_secretsmanager_secret_version" "ladybugs" {
  count = var.create_secrets_manager ? 1 : 0

  secret_id     = aws_secretsmanager_secret.ladybugs[0].id
  secret_string = jsonencode(var.ladybugs_env_vars)
}

# =============================================================================
# IAM Role for EC2 (Required when using Secrets Manager)
# =============================================================================

# IAM role for EC2 instance to access Secrets Manager
resource "aws_iam_role" "ladybugs_ec2" {
  count = local.use_secrets_manager ? 1 : 0

  name = "${var.project_name}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-ec2-role"
    Environment = var.environment
    Project     = var.project_name
  }
}

# IAM policy to allow reading the specific secret
resource "aws_iam_role_policy" "secrets_manager_read" {
  count = local.use_secrets_manager ? 1 : 0

  name = "${var.project_name}-secrets-read"
  role = aws_iam_role.ladybugs_ec2[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = local.secrets_manager_arn
      }
    ]
  })
}

# Instance profile to attach the role to EC2
resource "aws_iam_instance_profile" "ladybugs" {
  count = local.use_secrets_manager ? 1 : 0

  name = "${var.project_name}-${var.environment}-ec2-profile"
  role = aws_iam_role.ladybugs_ec2[0].name

  tags = {
    Name        = "${var.project_name}-ec2-profile"
    Environment = var.environment
    Project     = var.project_name
  }
}

# EC2 Instance
resource "aws_instance" "ladybugs" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = var.key_name != "" ? var.key_name : null
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ladybugs.id]

  # Attach IAM instance profile when using Secrets Manager
  iam_instance_profile = local.use_secrets_manager ? aws_iam_instance_profile.ladybugs[0].name : null

  root_block_device {
    volume_size           = var.volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    docker_hub_token        = var.docker_hub_token
    env_content             = local.env_content
    use_secrets_manager     = local.use_secrets_manager
    secrets_manager_arn     = local.secrets_manager_arn
    aws_region              = var.aws_region
  }))

  tags = {
    Name        = "${var.project_name}-server"
    Environment = var.environment
    Project     = var.project_name
  }

  lifecycle {
    # Prevent accidental destruction
    prevent_destroy = false
  }

  # Ensure IAM role and Secrets Manager are created before the instance
  depends_on = [
    aws_iam_instance_profile.ladybugs,
    aws_secretsmanager_secret_version.ladybugs
  ]
}

# =============================================================================
# API Gateway - Provides HTTPS with valid SSL certificate for webhooks
# =============================================================================

# HTTP API (v2) - simpler and cheaper than REST API
resource "aws_apigatewayv2_api" "ladybugs" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"
  description   = "API Gateway for Ladybugs - provides HTTPS with valid SSL for webhooks"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["*"]
    max_age       = 300
  }

  tags = {
    Name        = "${var.project_name}-api-gateway"
    Environment = var.environment
    Project     = var.project_name
  }
}

# Integration for proxy routes - passes path to EC2
resource "aws_apigatewayv2_integration" "proxy" {
  api_id             = aws_apigatewayv2_api.ladybugs.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${aws_eip.ladybugs.public_ip}:5000/{proxy}"

  timeout_milliseconds = 30000
}

# Integration for root path - no path parameter
resource "aws_apigatewayv2_integration" "root" {
  api_id             = aws_apigatewayv2_api.ladybugs.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${aws_eip.ladybugs.public_ip}:5000"

  timeout_milliseconds = 30000
}

# Proxy route - handles all paths with path parameters
resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.ladybugs.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.proxy.id}"
}

# Root route - handles requests to /
resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.ladybugs.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.root.id}"
}

# Stage - deploys the API (using $default stage for simplicity)
resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.ladybugs.id
  name        = "$default"
  auto_deploy = true

  tags = {
    Name        = "${var.project_name}-api-stage"
    Environment = var.environment
    Project     = var.project_name
  }
}
