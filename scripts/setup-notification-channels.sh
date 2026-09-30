#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Notification Channels Setup Script

PROMETHEUS_CONTAINER="${PROMETHEUS_CONTAINER:-prometheus}"
ALERTMANAGER_CONTAINER="${ALERTMANAGER_CONTAINER:-alertmanager}"
SECRETS_DIR="${SECRETS_DIR:-$REPO_ROOT/prometheus/alertmanager-secrets}"

echo "Setting up notification channels..."

# Alertmanager does not expand ${VAR} in its config file, so credentials are
# supplied as one-value files under /etc/alertmanager/secrets, bind-mounted from
# prometheus/alertmanager-secrets. This script materialises them from the
# environment so no secret ever needs to be committed or hand-edited into YAML.
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

write_secret() {
    local name="$1" value="${2:-}"
    local path="$SECRETS_DIR/$name"

    if [ -z "$value" ]; then
        if [ -f "$path" ]; then
            echo "  keep   $name (no value supplied, existing file retained)"
            return 0
        fi
        echo "  SKIP   $name (no value supplied)"
        return 0
    fi

    printf '%s' "$value" > "$path"
    chmod 600 "$path"
    echo "  write  $name"
}

echo "Writing notification secrets to $SECRETS_DIR"
write_secret smtp_username "${SMTP_USERNAME:-}"
write_secret smtp_password "${SMTP_PASSWORD:-}"
write_secret slack_webhook_url "${SLACK_WEBHOOK_URL:-}"
write_secret pagerduty_routing_key "${PAGERDUTY_ROUTING_KEY:-}"

missing=0
for required in smtp_password slack_webhook_url pagerduty_routing_key; do
    if [ ! -s "$SECRETS_DIR/$required" ]; then
        echo "  WARNING: $required is empty; the matching receiver will fail to load." >&2
        missing=1
    fi
done

# Copy Alertmanager configuration to container
docker cp "$REPO_ROOT/prometheus/alertmanager.yml" "$ALERTMANAGER_CONTAINER":/etc/alertmanager/alertmanager.yml

# Restart Alertmanager to apply configuration
docker restart "$ALERTMANAGER_CONTAINER"

# Wait for Alertmanager to start
echo "Waiting for Alertmanager to restart..."
sleep 10

# Confirm it actually loaded the config rather than crash-looping on a bad file.
if docker exec "$ALERTMANAGER_CONTAINER" amtool check-config /etc/alertmanager/alertmanager.yml >/dev/null 2>&1; then
    echo "Alertmanager configuration is valid."
else
    echo "ERROR: Alertmanager rejected its configuration:" >&2
    docker exec "$ALERTMANAGER_CONTAINER" amtool check-config /etc/alertmanager/alertmanager.yml >&2 || true
    exit 1
fi

# Update Prometheus to use Alertmanager
echo "Configuring Prometheus to use Alertmanager..."
docker exec "$PROMETHEUS_CONTAINER" sed -i 's/alertmanagers:/alertmanagers:\n    - static_configs:\n        - targets:\n            - alertmanager:9093/' /etc/prometheus/prometheus.yml

# Restart Prometheus to apply Alertmanager configuration
docker restart "$PROMETHEUS_CONTAINER"

# Wait for Prometheus to restart
echo "Waiting for Prometheus to restart..."
sleep 10

echo "Notification channels configured successfully."
if [ "$missing" -ne 0 ]; then
    echo "Supply SMTP_PASSWORD, SLACK_WEBHOOK_URL and PAGERDUTY_ROUTING_KEY and re-run to enable all receivers."
fi
echo ""
echo "Access Alertmanager at http://localhost:9093 to verify configuration"
echo "Access Prometheus at http://localhost:9091 to view alert status"
