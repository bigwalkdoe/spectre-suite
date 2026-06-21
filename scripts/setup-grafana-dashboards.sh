#!/bin/bash
# Grafana Dashboard Setup Script

GRAFANA_URL="http://localhost:3002"
GRAFANA_USER="admin"
GRAFANA_PASSWORD="admin"

echo "Setting up Grafana dashboards and data sources..."

# Wait for Grafana to be ready
echo "Waiting for Grafana to start..."
sleep 10

# Change default password
echo "Changing default Grafana password..."
curl -s -X POST -H "Content-Type: application/json" \
  -d '{"oldPassword":"admin","newPassword":"admin123","confirmNewPassword":"admin123"}' \
  "${GRAFANA_URL}/api/user/password" \
  -u admin:admin

GRAFANA_PASSWORD="admin123"

# Add Prometheus data source
echo "Adding Prometheus data source..."
curl -s -X POST -H "Content-Type: application/json" \
  -d '{
    "name": "Prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
    "access": "proxy",
    "isDefault": true
  }' \
  "${GRAFANA_URL}/api/datasources" \
  -u admin:${GRAFANA_PASSWORD}

# Import System Monitoring Dashboard
echo "Importing System Monitoring Dashboard..."
SYSTEM_DASHBOARD=$(cat /home/deon/github/system-maintenance/grafana-dashboards/system-monitoring.json)
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"dashboard\":${SYSTEM_DASHBOARD},\"overwrite\":true,\"message\":\"Imported via script\"}" \
  "${GRAFANA_URL}/api/dashboards/db" \
  -u admin:${GRAFANA_PASSWORD}

# Import PostgreSQL Monitoring Dashboard
echo "Importing PostgreSQL Monitoring Dashboard..."
POSTGRES_DASHBOARD=$(cat /home/deon/github/system-maintenance/grafana-dashboards/postgresql-monitoring.json)
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"dashboard\":${POSTGRES_DASHBOARD},\"overwrite\":true,\"message\":\"Imported via script\"}" \
  "${GRAFANA_URL}/api/dashboards/db" \
  -u admin:${GRAFANA_PASSWORD}

# Import Redis Monitoring Dashboard
echo "Importing Redis Monitoring Dashboard..."
REDIS_DASHBOARD=$(cat /home/deon/github/system-maintenance/grafana-dashboards/redis-monitoring.json)
curl -s -X POST -H "Content-Type: application/json" \
  -d "{\"dashboard\":${REDIS_DASHBOARD},\"overwrite\":true,\"message\":\"Imported via script\"}" \
  "${GRAFANA_URL}/api/dashboards/db" \
  -u admin:${GRAFANA_PASSWORD}

echo "Grafana setup complete!"
echo "Access Grafana at: ${GRAFANA_URL}"
echo "Username: admin"
echo "Password: admin123"
