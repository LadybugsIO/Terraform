# Ladybugs Terraform Deployment

Deploy Ladybugs to AWS with a single Terraform command. This module provisions a complete infrastructure including EC2, VPC, and API Gateway with HTTPS.

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.0
- AWS account with appropriate permissions (see [IAM Policy](#iam-policy))
- AWS CLI configured (`aws configure`)
- Docker Hub access token (provided by Ladybugs team)
- OpenRouter API key

## Quick Start

```bash
# 1. Clone and navigate to the module
cd aws-ec2

# 2. Create your configuration
cp terraform.tfvars.example terraform.tfvars

# 3. Edit terraform.tfvars with your values
#    - Add your Docker Hub token
#    - Add your OpenRouter API key
#    - Optionally configure Slack/Jira integrations

# 4. Deploy
terraform init
terraform plan
terraform apply
```

## What Gets Deployed

| Resource | Description |
|----------|-------------|
| VPC | Isolated network (10.0.0.0/16) with public subnet |
| EC2 Instance | Amazon Linux 2023, t3.large (configurable) |
| Elastic IP | Static public IP address |
| Security Group | Controlled access to SSH, API, Neo4j, Seq |
| API Gateway | HTTPS endpoint with valid SSL certificate |

## Configuration

Edit `terraform.tfvars` to customize your deployment:

### Required Variables

| Variable | Description |
|----------|-------------|
| `docker_hub_token` | Docker Hub token for pulling Ladybugs images |
| `ladybugs_env_vars.OPEN_ROUTER_API_KEY` | OpenRouter API key for AI features |

### Optional Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | us-east-1 | AWS region |
| `instance_type` | t3.large | EC2 instance type |
| `volume_size` | 50 | EBS volume size (GB) |
| `key_name` | "" | EC2 key pair for SSH access |
| `allowed_ssh_cidrs` | ["0.0.0.0/0"] | IPs allowed to SSH |
| `allowed_api_cidrs` | ["0.0.0.0/0"] | IPs allowed to access services |

### Integrations

Configure these in `ladybugs_env_vars`:

```hcl
ladybugs_env_vars = {
  "OPEN_ROUTER_API_KEY" = "your-key"

  # Slack
  "SLACK_BOT_TOKEN"       = "xoxb-..."
  "SLACK_SIGNING_SECRET"  = "..."

  # Jira
  "JIRA_WEBHOOK_SECRET"   = "..."

  # Log Sources
  "CLOUDWATCH_ACCESS_KEY_ID"     = "..."
  "CLOUDWATCH_SECRET_ACCESS_KEY" = "..."
  "CORALOGIX_API_KEY"            = "..."
  "GRAFANA_API_KEY"              = "..."
}
```

## Outputs

After deployment, Terraform displays:

| Output | Description |
|--------|-------------|
| `api_gateway_url` | HTTPS URL for webhooks (Slack, Jira) |
| `swagger_docs_url` | API documentation |
| `public_ip` | EC2 public IP |
| `neo4j_browser_url` | Neo4j database UI |
| `seq_logs_url` | Application logs UI |
| `ssh_command` | SSH connection command |

## Post-Deployment

### Verify Installation

```bash
# SSH into the instance
ssh -i your-key.pem ec2-user@<public_ip>

# Check installation logs
sudo cat /var/log/ladybugs-install.log

# Check running containers
cd /opt/ladybugs && sudo docker compose ps

# View application logs
sudo docker compose logs -f
```

### Configure Webhooks

Use the `api_gateway_url` output for webhook integrations:
- **Slack**: `https://<api_gateway_url>/slack/events`
- **Jira**: `https://<api_gateway_url>/jira/webhook`

The API Gateway provides a valid SSL certificate required by Slack and Jira.

## IAM Policy

The `aws-ec2/iam-policy.json` file contains the minimum AWS permissions required to deploy this infrastructure. Create an IAM user or role with this policy attached.

## Instance Sizing

| Type | vCPU | RAM | Use Case |
|------|------|-----|----------|
| t3.medium | 2 | 4 GB | Development/Testing |
| t3.large | 2 | 8 GB | Production (recommended) |
| t3.xlarge | 4 | 16 GB | Heavy usage |

## Destroying Infrastructure

```bash
terraform destroy
```

This removes all AWS resources created by this module.

## Troubleshooting

### Services not starting
```bash
# Check Docker status
sudo systemctl status docker

# Check Ladybugs service
sudo systemctl status ladybugs

# View detailed logs
sudo cat /var/log/ladybugs-install.log
```

### Cannot pull Docker images
Verify your Docker Hub token is correct and has access to `ladybugsio/ladybugs`.

### Webhook not working
Ensure you're using the `api_gateway_url` (HTTPS), not the direct EC2 IP (HTTP).

## Support

Contact the Ladybugs team for assistance with:
- Docker Hub access tokens
- API key issues
- Integration configuration