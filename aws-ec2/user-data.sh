#!/bin/bash
set -e

# Ladybugs EC2 Bootstrap Script
# This script runs on first boot to install Docker and deploy Ladybugs

exec > >(tee /var/log/ladybugs-install.log) 2>&1
echo "Starting Ladybugs installation at $(date)"

# Configuration
INSTALL_DIR="/opt/ladybugs"
BASE_URL="https://static.ladybugs.io"
DOCKER_COMPOSE_URL="$BASE_URL/docker-compose.published.yml"
ENV_EXAMPLE_URL="$BASE_URL/.env.docker.example"
DOCKER_IMAGE="ladybugsio/ladybugs"

# Secrets Manager configuration (set by Terraform)
USE_SECRETS_MANAGER="${use_secrets_manager}"
SECRETS_MANAGER_ARN="${secrets_manager_arn}"
AWS_REGION="${aws_region}"

# CloudWatch monitoring configuration (set by Terraform)
ENABLE_CLOUDWATCH_MONITORING="${enable_cloudwatch_monitoring}"
PROJECT_NAME="${project_name}"

# Create install directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Install Docker
echo "Installing Docker..."
dnf update -y
dnf install -y docker

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Install Docker Compose plugin
echo "Installing Docker Compose..."
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Verify installations
docker --version
docker compose version

# Login to Docker Hub
echo "Logging in to Docker Hub..."
echo "${docker_hub_token}" | docker login -u ladybugsio --password-stdin

# Download docker-compose.yml
echo "Downloading docker-compose.yml..."
curl -fsSL "$DOCKER_COMPOSE_URL" -o docker-compose.yml

# Download .env template
echo "Downloading .env template..."
curl -fsSL "$ENV_EXAMPLE_URL" -o .env.example

# Configure environment variables
echo "Configuring environment variables..."

if [ "$USE_SECRETS_MANAGER" = "true" ]; then
    echo "Fetching environment variables from AWS Secrets Manager..."

    # Install jq for JSON parsing (if not already installed)
    if ! command -v jq &> /dev/null; then
        echo "Installing jq..."
        dnf install -y jq
    fi

    # Fetch secret from Secrets Manager and convert JSON to .env format
    # The secret is stored as JSON: {"KEY1": "value1", "KEY2": "value2"}
    aws secretsmanager get-secret-value \
        --secret-id "$SECRETS_MANAGER_ARN" \
        --region "$AWS_REGION" \
        --query 'SecretString' \
        --output text | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > .env

    echo "Environment variables loaded from Secrets Manager"

    # Create a script to refresh secrets (can be run manually or via cron)
    cat > /opt/ladybugs/refresh-secrets.sh << 'REFRESH_EOF'
#!/bin/bash
# Refresh environment variables from Secrets Manager
# Run this script to pull latest secrets without redeploying

set -e
cd /opt/ladybugs

echo "Fetching latest secrets from Secrets Manager..."
aws secretsmanager get-secret-value \
    --secret-id "$SECRETS_MANAGER_ARN" \
    --region "$AWS_REGION" \
    --query 'SecretString' \
    --output text | jq -r 'to_entries | .[] | "\(.key)=\(.value)"' > .env.new

# Backup current .env and replace
if [ -f .env ]; then
    cp .env .env.backup
fi
mv .env.new .env

echo "Secrets refreshed. Restart containers to apply:"
echo "  cd /opt/ladybugs && docker compose down && docker compose up -d"
REFRESH_EOF

    # Inject the actual ARN and region into the refresh script
    sed -i "s|\$SECRETS_MANAGER_ARN|$SECRETS_MANAGER_ARN|g" /opt/ladybugs/refresh-secrets.sh
    sed -i "s|\$AWS_REGION|$AWS_REGION|g" /opt/ladybugs/refresh-secrets.sh
    chmod +x /opt/ladybugs/refresh-secrets.sh

else
    # Direct mode: Write environment variables from Terraform
    cat > .env << 'ENVEOF'
${env_content}
ENVEOF
fi

# If no env vars provided, use the example file
if [ ! -s .env ]; then
    echo "No environment variables provided, using example file..."
    cp .env.example .env
fi

# Pull images
echo "Pulling Docker images..."
docker compose pull

# Start services
echo "Starting Ladybugs services..."
docker compose up -d

# =============================================================================
# CloudWatch Agent Installation (for CPU, Memory, Disk metrics)
# =============================================================================
if [ "$ENABLE_CLOUDWATCH_MONITORING" = "true" ]; then
    echo "Installing CloudWatch Agent..."

    # Download and install CloudWatch Agent
    dnf install -y amazon-cloudwatch-agent

    # Create CloudWatch Agent configuration
    cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << CWEOF
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "metrics": {
        "namespace": "$PROJECT_NAME",
        "append_dimensions": {
            "InstanceId": "\$${aws:InstanceId}"
        },
        "aggregation_dimensions": [["InstanceId"]],
        "metrics_collected": {
            "cpu": {
                "measurement": [
                    "cpu_usage_idle",
                    "cpu_usage_user",
                    "cpu_usage_system",
                    "cpu_usage_iowait"
                ],
                "metrics_collection_interval": 60,
                "totalcpu": true,
                "resources": ["*"]
            },
            "mem": {
                "measurement": [
                    "mem_used_percent",
                    "mem_used",
                    "mem_available",
                    "mem_total"
                ],
                "metrics_collection_interval": 60
            },
            "disk": {
                "measurement": [
                    "disk_used_percent",
                    "disk_used",
                    "disk_free"
                ],
                "metrics_collection_interval": 60,
                "resources": ["/"]
            },
            "diskio": {
                "measurement": [
                    "diskio_reads",
                    "diskio_writes",
                    "diskio_read_bytes",
                    "diskio_write_bytes"
                ],
                "metrics_collection_interval": 60,
                "resources": ["*"]
            },
            "netstat": {
                "measurement": [
                    "netstat_tcp_established",
                    "netstat_tcp_time_wait"
                ],
                "metrics_collection_interval": 60
            }
        }
    }
}
CWEOF

    # Start CloudWatch Agent
    echo "Starting CloudWatch Agent..."
    /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
        -a fetch-config \
        -m ec2 \
        -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
        -s

    # Enable CloudWatch Agent to start on boot
    systemctl enable amazon-cloudwatch-agent

    echo "CloudWatch Agent installed and started successfully"
fi

# Create systemd service for auto-start on reboot
cat > /etc/systemd/system/ladybugs.service << 'EOF'
[Unit]
Description=Ladybugs Docker Compose Application
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/ladybugs
ExecStart=/usr/local/lib/docker/cli-plugins/docker-compose up -d
ExecStop=/usr/local/lib/docker/cli-plugins/docker-compose down
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable ladybugs.service

echo ""
echo "========================================"
echo "Ladybugs installation complete!"
echo "========================================"
echo ""
echo "Services are starting up. It may take a few minutes for all services to be ready."
echo ""
echo "Installation completed at $(date)"
