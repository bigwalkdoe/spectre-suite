#!/bin/bash
set -euo pipefail
# Docker Image Vulnerability Scanner

echo "Scanning Docker images for vulnerabilities..."

# Install Trivy if not available
if ! command -v trivy >/dev/null 2>&1; then
    echo "Installing Trivy vulnerability scanner..."
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y trivy || true
    fi
    if ! command -v trivy >/dev/null 2>&1; then
        # Install from release if not in repo
        wget -qO - https://github.com/aquasecurity/trivy/releases/download/v0.50.0/trivy_0.50.0_Linux-64bit.tar.gz | tar -xz
        sudo mv trivy /usr/local/bin/
        sudo chmod +x /usr/local/bin/trivy
    fi
fi

if ! command -v trivy >/dev/null 2>&1; then
    echo "Trivy is not installed. Please install it first." >&2
    exit 1
fi

# Scan running containers
if command -v docker >/dev/null 2>&1; then
    echo "Scanning running containers..."
    mapfile -t images < <(docker ps --format "{{.Image}}" | sort -u)
    if [[ ${#images[@]} -eq 0 ]]; then
        echo "No running containers/images to scan."
    else
        for image in "${images[@]}"; do
            [[ -n "$image" ]] || continue
            echo "Scanning image: $image"
            trivy image --severity HIGH,CRITICAL "$image" || echo "Failed to scan $image"
        done
    fi
else
    echo "Docker is not installed or not running" >&2
fi

echo "Docker image scanning completed!"
