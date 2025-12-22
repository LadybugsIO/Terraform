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
