# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-12-22

### Added

- Initial release of Ladybugs AWS Terraform module
- **Infrastructure**
  - VPC with public subnet and internet gateway
  - EC2 instance with Amazon Linux 2023
  - Elastic IP for stable public addressing
  - Security group with configurable access rules
  - Encrypted EBS volume (gp3)
- **API Gateway**
  - HTTP API with automatic HTTPS/SSL
  - CORS configuration for web clients
  - Proxy routing to EC2 backend
- **Automation**
  - User data script for automated Docker installation
  - Systemd service for auto-restart on reboot
  - Docker Compose deployment from static.ladybugs.io
- **Configuration**
  - Configurable instance type and volume size
  - Environment variable injection via Terraform
  - Example tfvars with all available options
- **Documentation**
  - IAM policy with least-privilege permissions
  - terraform.tfvars.example with integration examples
