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

# Write environment variables from Terraform
echo "Configuring environment variables..."
cat > .env << 'ENVEOF'
${env_content}
ENVEOF

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
