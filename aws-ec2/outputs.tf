# Ladybugs Terraform Outputs
# These values are displayed after terraform apply

output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.ladybugs.id
}

output "public_ip" {
  description = "Public IP address (Elastic IP)"
  value       = aws_eip.ladybugs.public_ip
}

# =============================================================================
# API Gateway (HTTPS with valid SSL - use for webhooks)
# =============================================================================

output "api_gateway_url" {
  description = "API Gateway URL (HTTPS) - USE THIS FOR WEBHOOKS"
  value       = aws_apigatewayv2_api.ladybugs.api_endpoint
}

output "webhook_url" {
  description = "Webhook URL for Slack/Jira (HTTPS with valid SSL)"
  value       = aws_apigatewayv2_api.ladybugs.api_endpoint
}

output "swagger_docs_url" {
  description = "Swagger documentation URL (via API Gateway)"
  value       = "${aws_apigatewayv2_api.ladybugs.api_endpoint}/docs"
}

# =============================================================================
# Direct EC2 Access (HTTP - for admin tools)
# =============================================================================

output "api_url_direct" {
  description = "Direct EC2 API URL (HTTP)"
  value       = "http://${aws_eip.ladybugs.public_ip}:5000"
}

output "neo4j_browser_url" {
  description = "Neo4j Browser URL (HTTP)"
  value       = "http://${aws_eip.ladybugs.public_ip}:7474"
}

output "seq_logs_url" {
  description = "Seq Logs UI URL (HTTP)"
  value       = "http://${aws_eip.ladybugs.public_ip}:5341"
}

# =============================================================================
# Connection Commands
# =============================================================================

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = var.key_name != "" ? "ssh -i <your-key.pem> ec2-user@${aws_eip.ladybugs.public_ip}" : "No SSH key configured"
}

output "install_log_command" {
  description = "Command to view installation logs"
  value       = "sudo cat /var/log/ladybugs-install.log"
}

output "docker_logs_command" {
  description = "Command to view Docker logs"
  value       = "cd /opt/ladybugs && sudo docker compose logs -f"
}

# =============================================================================
# Secrets Manager (when enabled)
# =============================================================================

output "secrets_manager_arn" {
  description = "ARN of the Secrets Manager secret (if using Secrets Manager)"
  value       = local.use_secrets_manager ? local.secrets_manager_arn : null
}

output "secrets_manager_name" {
  description = "Name of the Secrets Manager secret (if created by this module)"
  value       = var.create_secrets_manager ? aws_secretsmanager_secret.ladybugs[0].name : null
}

output "refresh_secrets_command" {
  description = "Command to refresh secrets from Secrets Manager (run on EC2 instance)"
  value       = local.use_secrets_manager ? "sudo /opt/ladybugs/refresh-secrets.sh" : "Secrets Manager not enabled"
}

# =============================================================================
# CloudWatch Monitoring (when enabled)
# =============================================================================

output "cloudwatch_metrics_url" {
  description = "CloudWatch Metrics console URL for the Ladybugs namespace"
  value       = var.enable_cloudwatch_monitoring ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#metricsV2?graph=~()&query=~'*7bCWAgent*2cInstanceId*7d" : "CloudWatch monitoring not enabled"
}

output "cloudwatch_ec2_dashboard_url" {
  description = "CloudWatch EC2 dashboard URL for this instance"
  value       = var.enable_cloudwatch_monitoring ? "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#home:dashboards/EC2?~(alarmStateFilter~'ALARM)" : "CloudWatch monitoring not enabled"
}

output "cloudwatch_agent_status_command" {
  description = "Command to check CloudWatch Agent status (run on EC2 instance)"
  value       = var.enable_cloudwatch_monitoring ? "sudo /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -m ec2 -a status" : "CloudWatch monitoring not enabled"
}
