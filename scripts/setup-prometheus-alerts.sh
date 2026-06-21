#!/bin/bash
# Prometheus Alert Rules Setup Script

echo "Setting up Prometheus alert rules..."

# Copy alert rules to Prometheus container
docker cp /home/deon/github/system-maintenance/prometheus/alert_rules.yml guardrail-ai-prometheus-1:/etc/prometheus/alert_rules.yml

# Restart Prometheus to load new rules
docker restart guardrail-ai-prometheus-1

# Wait for Prometheus to start
echo "Waiting for Prometheus to restart..."
sleep 10

# Verify rules are loaded
echo "Verifying alert rules are loaded..."
docker exec guardrail-ai-prometheus-1 promtool check config /etc/prometheus/prometheus.yml

echo "Prometheus alert rules configured successfully!"
echo "Access Prometheus at http://localhost:9091 to view alerts"
