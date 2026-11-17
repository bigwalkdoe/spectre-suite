#!/bin/bash
set -euo pipefail

# Docker Resource Optimization Script
# Adds resource limits to a Docker Compose project via docker-compose.override.yml.
#
# Target resolution:
#   1) DOCKER_COMPOSE_PROJECT_DIR (explicit project directory)
#   2) Current working directory, if it contains a compose file
#
# To apply limits you can set DOCKER_COMPOSE_PROJECT_DIR=/path/to/project

echo "Optimizing Docker container resource limits..."

if [[ -n "${DOCKER_COMPOSE_PROJECT_DIR:-}" ]]; then
    PROJECT_DIR="$DOCKER_COMPOSE_PROJECT_DIR"
elif [[ -f "docker-compose.yml" || -f "docker-compose.yaml" || -f "compose.yml" || -f "compose.yaml" ]]; then
    PROJECT_DIR="$PWD"
else
    echo "No Docker Compose project found." >&2
    echo "Set DOCKER_COMPOSE_PROJECT_DIR to a directory containing a compose file and rerun." >&2
    exit 1
fi

cd "$PROJECT_DIR"

# Locate compose file
COMPOSE_FILE=""
for candidate in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
    if [[ -f "$candidate" ]]; then
        COMPOSE_FILE="$candidate"
        break
    fi
done

if [[ -z "$COMPOSE_FILE" ]]; then
    echo "No compose file found in $PROJECT_DIR" >&2
    exit 1
fi

echo "Target project: $PROJECT_DIR ($COMPOSE_FILE)"

# Check if current docker-compose has resource limits
if ! grep -q "deploy:" "$COMPOSE_FILE"; then
    echo "Adding resource limits to docker-compose.override.yml"

    # Add resource limits to key services
    # This will be added as a separate optimization file
    cat > docker-compose.override.yml << 'EOF'
version: '3.8'

services:
  postgres:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  neo4j:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 4G
        reservations:
          cpus: '1.0'
          memory: 2G

  redis:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M

  api:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 512M

  celery-worker:
    deploy:
      resources:
        limits:
          cpus: '2.0'
          memory: 2G
        reservations:
          cpus: '1.0'
          memory: 512M

  prometheus:
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  grafana:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M

  cadvisor:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M
EOF

    echo "Resource limits added to docker-compose.override.yml"
    echo "Restart containers to apply: docker compose up -d (or docker-compose up -d)"
else
    echo "Resource limits already configured in $COMPOSE_FILE"
fi
