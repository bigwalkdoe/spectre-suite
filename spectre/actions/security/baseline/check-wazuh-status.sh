#!/bin/bash
# Spectre Security Baseline — Wazuh agent status (additive, read-only helper)
set -euo pipefail
echo "=== Wazuh Agent Status ==="
if [ -f /var/ossec/bin/wazuh-agent ] || [ -x /var/ossec/bin/wazuh-control ]; then
  /var/ossec/bin/wazuh-agent -c 2>/dev/null || echo "Wazuh agent check unavailable/not connected"
  systemctl status wazuh-agent --no-pager 2>/dev/null || echo "Wazuh service not found/inactive"
  if [ -f /var/ossec/logs/ossec.log ]; then echo "Agent log: /var/ossec/logs/ossec.log"; fi
else
  echo "Wazuh agent not installed"
fi
exit 0
