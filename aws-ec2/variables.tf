# Ladybugs Terraform Variables
# Copy terraform.tfvars.example to terraform.tfvars and customize

# AWS Configuration
variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

# Instance Configuration
variable "instance_type" {
  description = "EC2 instance type (t3.large recommended for production)"
  type        = string
  default     = "t3.large"
}

variable "volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 50
}

variable "key_name" {
  description = "Name of existing EC2 key pair for SSH access (leave empty to skip SSH key)"
  type        = string
  default     = ""
}

# Network Configuration
variable "allowed_ssh_cidrs" {
  description = "CIDR blocks allowed to SSH (set to your IP for security)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_api_cidrs" {
  description = "CIDR blocks allowed to access the API and services"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Ladybugs Configuration
variable "docker_hub_token" {
  description = "Docker Hub access token for pulling Ladybugs image"
  type        = string
  sensitive   = true
}

variable "ladybugs_env_vars" {
  description = "Environment variables for Ladybugs (will be written to .env file)"
  type        = map(string)
  default     = {}
  sensitive   = true
}

# Tags
variable "environment" {
  description = "Environment name (e.g., production, staging)"
  type        = string
  default     = "production"
}

variable "project_name" {
  description = "Project name for resource tagging"
  type        = string
  default     = "ladybugs"
}
