#!/bin/bash
# Docker Image Vulnerability Scanner

echo "Scanning Docker images for vulnerabilities..."

# Check if Trivy is available
if ! command -v trivy >/dev/null 2>&1; then
    echo "Trivy is not installed. Please install it first."
    exit 1
fi

# Scan running containers
if command -v docker >/dev/null 2>&1; then
    echo "Scanning running containers..."
    docker ps --format "{{.Image}}" | sort -u | while read image; do
        echo "Scanning image: $image"
        trivy image --severity HIGH,CRITICAL "$image" || echo "Failed to scan $image"
    done
else
    echo "Docker is not installed or not running"
fi

echo "Docker image scanning completed!"
