#!/bin/bash
# Align/verify enhanced monitoring components (non-destructive).
# Mutating curated Prometheus/Alertmanager/Compose files is unsafe here; this
# script reports drift and performs only idempotent, non-conflicting setup.
set -euo pipefail

echo "=== Enhanced Monitoring Alignment Check ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ok=0
warn=0

check() {
  local label="$1" path="$2" pattern="$3"
  if grep -q "$pattern" "$path" 2>/dev/null; then
    echo "  [ok]   $label"
    ok=$((ok + 1))
  else
    echo "  [warn] $label (missing in ${path#"$PROJECT_ROOT"/})"
    warn=$((warn + 1))
  fi
}

# 1. Blackbox exporter present in compose and Prometheus
check "Blackbox service in compose" "$PROJECT_ROOT/docker-compose.monitoring.yml" "blackbox-exporter"
check "Blackbox HTTP job in Prometheus" "$PROJECT_ROOT/prometheus/prometheus.yml" "blackbox-http"
check "Blackbox TCP job in Prometheus" "$PROJECT_ROOT/prometheus/prometheus.yml" "blackbox-tcp"

# 2. Alertmanager templates (canonical location) and wiring
mkdir -p "$PROJECT_ROOT/prometheus/templates"
echo "  [ok]   Alertmanager templates directory present"
ok=$((ok + 1))
check "Alertmanager templates configured" "$PROJECT_ROOT/prometheus/alertmanager.yml" '^templates:'
check "Alertmanager templates mounted" "$PROJECT_ROOT/docker-compose.monitoring.yml" "/etc/alertmanager/templates"

# 3. Uptime/business alert rules (curated names)
check "UptimeCheckFailed rule" "$PROJECT_ROOT/prometheus/alert_rules.yml" "UptimeCheckFailed"
check "HighEndpointLatency rule" "$PROJECT_ROOT/prometheus/alert_rules.yml" "HighEndpointLatency"

# 4. Business metrics exporter cron (idempotent)
if crontab -l 2>/dev/null | grep -q "business-metrics-exporter"; then
  echo "  [ok]   Business metrics exporter cron entry present"
  ok=$((ok + 1))
else
  echo "  [warn] Business metrics exporter not scheduled (see README: cron required)"
  warn=$((warn + 1))
fi

echo ""
echo "Summary: $ok ok, $warn warning(s)."
if [[ "$warn" -gt 0 ]]; then
  echo "Review curated config files; this script does not append to compose/prometheus/alert rules."
  exit 1
fi

echo "Enhanced monitoring configuration is aligned. Restart to apply if needed:"
echo "  docker compose -f docker-compose.monitoring.yml up -d"
