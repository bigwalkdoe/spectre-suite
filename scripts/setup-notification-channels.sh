#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-$PROMETHEUS_CONTAINER}"
ALERTMANAGER_CONTAINER="${ALERTMANAGER_CONTAINER:-$ALERTMANAGER_CONTAINER}"
# Notification Channels Setup Script

echo "Setting up notification channels..."

# Copy Alertmanager configuration to container
docker cp $REPO_ROOT/prometheus/alertmanager.yml $ALERTMANAGER_CONTAINER:/etc/alertmanager/alertmanager.yml

# Restart Alertmanager to apply configuration
docker restart $ALERTMANAGER_CONTAINER

# Wait for Alertmanager to start
echo "Waiting for Alertmanager to restart..."
sleep 10

# Update Prometheus to use Alertmanager
echo "Configuring Prometheus to use Alertmanager..."
docker exec $PROMETHEUS_CONTAINER sed -i 's/alertmanagers:/alertmanagers:\n    - static_configs:\n        - targets:\n            - alertmanager:9093/' /etc/prometheus/prometheus.yml

# Restart Prometheus to apply Alertmanager configuration
docker restart $PROMETHEUS_CONTAINER

# Wait for Prometheus to restart
echo "Waiting for Prometheus to restart..."
sleep 10

echo "Notification channels configured successfully!"
echo ""
echo "IMPORTANT: Update the following settings in prometheus/alertmanager.yml:"
echo "1. SMTP server and credentials for email notifications"
echo "2. Slack webhook URL for Slack notifications"
echo "3. Email addresses for notification recipients"
echo ""
echo "Access Alertmanager at http://localhost:9093 to verify configuration"
echo "Access Prometheus at http://localhost:9091 to view alert status"
