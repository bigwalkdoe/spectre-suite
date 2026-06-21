#!/bin/bash
# Docker Container Security Hardening

echo "Hardening Docker container security..."

# Create Docker security scan script
cat > /home/deon/scripts/security/scan-docker-images.sh << 'EOF'
#!/bin/bash
# Docker Image Vulnerability Scanner

echo "Scanning Docker images for vulnerabilities..."

# Install Trivy if not available
if ! command -v trivy >/dev/null 2>&1; then
    echo "Installing Trivy vulnerability scanner..."
    sudo dnf install -y trivy || {
        # Install from release if not in repo
        wget -qO - https://github.com/aquasecurity/trivy/releases/download/v0.50.0/trivy_0.50.0_Linux-64bit.tar.gz | tar -xz
        sudo mv trivy /usr/local/bin/
        sudo chmod +x /usr/local/bin/trivy
    }
fi

# Scan running containers
echo "Scanning running containers..."
docker ps --format "{{.Image}}" | sort -u | while read image; do
    echo "Scanning image: $image"
    trivy image --severity HIGH,CRITICAL "$image" || echo "Failed to scan $image"
done

echo "Docker image scanning completed!"
EOF

chmod +x /home/deon/scripts/security/scan-docker-images.sh

# Run Docker image scanning
echo "Running Docker image vulnerability scan..."
/home/deon/scripts/security/scan-docker-images.sh

# Set up Docker security policies
echo "Setting up Docker security policies..."

# Create Docker daemon security configuration
sudo bash -c 'cat > /etc/docker/daemon-security.json << "EOF"
{
  "live-restore": true,
  "userland-proxy": false,
  "no-new-privileges": true,
  "icc": false,
  "disable-legacy-registry": true,
  "default-runtime": "runc",
  "runtimes": {
    "runc": {
      "path": "runc",
      "runtimeArgs": []
    }
  }
}
EOF'

# Update Docker daemon configuration with security settings
sudo bash -c 'jq -s '.[0] * .[1]' /etc/docker/daemon.json /etc/docker/daemon-security.json > /tmp/daemon-merged.json'
sudo mv /tmp/daemon-merged.json /etc/docker/daemon.json

# Note: Docker restart required to apply these changes
echo "Docker security policies configured. Restart Docker to apply changes with: sudo systemctl restart docker"

echo "Docker security hardening completed!"
