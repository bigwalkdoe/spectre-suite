#!/bin/bash
# Spectre Security Baseline — Update baseline from live state (additive, mutating)
# Captures Docker container/network/compliance state into a spectre-security-compatible
# baseline JSON. Contract: matches security/test-data/current-infrastructure.json
# shape used by drift-detection.sh.
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_SECURITY_ROOT="${SPECTRE_SECURITY_ROOT:-~//dev/github/spectre-security}"
STATE_DIR="${SECURITY_BASELINE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre/security-baseline}"
mkdir -p "$STATE_DIR"

BASELINE_FILE="${SECURITY_BASELINE_FILE:-${SPECTRE_BASELINE:-$STATE_DIR/current-infrastructure.json}}"
BACKUP_FILE="${BASELINE_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

echo "=== Updating Infrastructure Baseline (suite-canonical helper) ==="
echo "Baseline: $BASELINE_FILE"
command -v docker >/dev/null 2>&1 || { echo "Docker not available" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }

if [ -f "$BASELINE_FILE" ]; then
  cp "$BASELINE_FILE" "$BACKUP_FILE"
  echo "Backed up existing baseline: $BACKUP_FILE"
else
  # Seed minimal compatible structure if missing.
  cat > "$BASELINE_FILE" <<'JSON'
{"docker":[],"network":{"open_ports":[]},"compliance":{},"updated":null,"updated_iso":null}
JSON
  echo "Created new baseline seed: $BASELINE_FILE"
fi

echo "Collecting live Docker container data..."
DOCKER_JSON=$(docker ps --format '{{.Names}}' 2>/dev/null | while read -r CONTAINER; do
  [ -n "$CONTAINER" ] || continue
  INSPECT=$(docker inspect "$CONTAINER" 2>/dev/null | jq '.[0]' || echo '{}')
  NAME=$(echo "$INSPECT" | jq -r '.Name | ltrimstr("/")')
  IMAGE=$(echo "$INSPECT" | jq -r '.Config.Image // ""')
  PRIVILEGED=$(echo "$INSPECT" | jq -r '.HostConfig.Privileged // false')
  MEMORY=$(echo "$INSPECT" | jq -r '.HostConfig.Memory // 0')
  HEALTH_TEST=$(echo "$INSPECT" | jq -r '.Config.Healthcheck.Test // [] | join(" ")' 2>/dev/null)
  [ "$HEALTH_TEST" = "null" ] && HEALTH_TEST=""
  PORTS=$(echo "$INSPECT" | jq -c '[.HostConfig.PortBindings // {} | to_entries[] | select(.value[0].HostPort != null and .value[0].HostPort != "") | {host_ip: (.value[0].HostIp // "0.0.0.0"), host_port: (.value[0].HostPort | tonumber), container_port: (.key | split("/")[0] | tonumber)}]')
  MOUNTS=$(echo "$INSPECT" | jq -c '[.Mounts[]? | {source: .Source, destination: .Destination, type: .Type}]')
  jq -n --arg name "$NAME" --arg image "$IMAGE" --argjson privileged "$PRIVILEGED" --argjson memory "$MEMORY" \
    --arg healthcheck "$HEALTH_TEST" --argjson ports "$PORTS" --argjson mounts "$MOUNTS" \
    '{name:$name,image:$image,privileged:$privileged,memory_limit:$memory,healthcheck:$healthcheck,ports:$ports,mounts:$mounts}'
done | jq -s '.')

NETWORK_PORTS=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oE '127\.0\.0\.1:[0-9]+|0\.0\.0\.0:[0-9]+|\[::\]:[0-9]+' | sed 's/.*://' | sort -nu || true)
if [ -z "$NETWORK_PORTS" ]; then NETWORK_PORTS_JSON='[]'; else NETWORK_PORTS_JSON=$(echo "$NETWORK_PORTS" | jq -R . | jq -s .); fi

echo "Collecting live compliance state..."
if command -v ufw >/dev/null 2>&1; then
  LIVE_FW=$(ufw status 2>/dev/null | grep -q "Status: active" && echo true || echo false)
elif command -v firewall-cmd >/dev/null 2>&1; then
  LIVE_FW=$(firewall-cmd --state 2>/dev/null | grep -q "running" && echo true || echo false)
else
  LIVE_FW=null
fi
LIVE_SSH_PASS=null
if [ -r /etc/ssh/sshd_config ]; then
  _ssh=$(grep -i "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | tr '[:upper:]' '[:lower:]' || echo "")
  if [ "$_ssh" = "yes" ]; then LIVE_SSH_PASS=true; elif [ "$_ssh" = "no" ]; then LIVE_SSH_PASS=false; fi
fi
if command -v auditctl >/dev/null 2>&1; then
  LIVE_AUDIT=$(systemctl is-active auditd 2>/dev/null | grep -q "active" && echo true || echo false)
else
  LIVE_AUDIT=null
fi
if systemctl is-active --quiet fail2ban 2>/dev/null || systemctl is-active --quiet crowdsec 2>/dev/null; then
  LIVE_IDS=true
else
  LIVE_IDS=false
fi
AIDE_DB="${SECURITY_AIDE_DB:-/var/lib/aide/aide.db.gz}"
if [ -f "$AIDE_DB" ] || [ -f "$SCRIPT_DIR/aide/aide.db.gz" ] || [ -f "$SPECTRE_SECURITY_ROOT/security/aide/aide.db.gz" ]; then
  LIVE_AIDE=true
else
  LIVE_AIDE=false
fi
LIVE_SCAN=false
(command -v trivy >/dev/null 2>&1 || command -v gitleaks >/dev/null 2>&1 || [ -x "${HOME}/go/bin/gitleaks" ]) && LIVE_SCAN=true

COMPLIANCE_JSON=$(jq -n \
  --argjson fw "$([ "$LIVE_FW" = null ] && echo null || echo "$LIVE_FW")" \
  --argjson ssh "$([ "$LIVE_SSH_PASS" = null ] && echo null || echo "$LIVE_SSH_PASS")" \
  --argjson audit "$([ "$LIVE_AUDIT" = null ] && echo null || echo "$LIVE_AUDIT")" \
  --argjson ids "$LIVE_IDS" \
  --argjson fim "$LIVE_AIDE" \
  --argjson scan "$LIVE_SCAN" \
  '({intrusion_detection_active:$ids,file_integrity_monitoring:$fim,security_scanning_enabled:$scan}
    + (if $fw==null then {} else {firewall_enabled:$fw} end)
    + (if $ssh==null then {} else {ssh_password_auth:$ssh} end)
    + (if $audit==null then {} else {audit_logging_enabled:$audit} end))')

jq --argjson docker "$DOCKER_JSON" --argjson ports "$NETWORK_PORTS_JSON" --argjson compliance "$COMPLIANCE_JSON" \
   '.docker = $docker | .network = ((.network // {}) + {open_ports: $ports}) | .compliance = ((.compliance // {}) * $compliance) | .updated = (now|floor) | .updated_iso = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
   "$BASELINE_FILE" > "$BASELINE_FILE.tmp" && mv "$BASELINE_FILE.tmp" "$BASELINE_FILE"

echo "Baseline updated: containers=$(echo "$DOCKER_JSON" | jq 'length') network_ports=$(echo "$NETWORK_PORTS_JSON" | jq 'length')"
echo "Compliance captured: $(echo "$COMPLIANCE_JSON" | jq -c '.')"
echo "Verify: SECURITY_BASELINE_FILE=$BASELINE_FILE bash spectre/actions/security/baseline/drift-detection.sh"
