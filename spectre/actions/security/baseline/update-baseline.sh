#!/bin/bash
# Spectre Security Baseline — Update baseline from live state (additive, mutating)
# Captures Docker container/network state into a spectre-security-compatible
# baseline JSON. Contract: matches security/test-data/current-infrastructure.json
# shape used by drift-detection.sh (compat adapter pending for suite policy schema).
set -euo pipefail

: "${HOME:=$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 2>/dev/null || true)}"
export HOME="${HOME:-/root}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
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

jq --argjson docker "$DOCKER_JSON" --argjson ports "$NETWORK_PORTS_JSON" \
   '.docker = $docker | .network.open_ports = $ports | .updated = now | .updated_iso = (now | strftime("%Y-%m-%dT%H:%M:%SZ"))' \
   "$BASELINE_FILE" > "$BASELINE_FILE.tmp" && mv "$BASELINE_FILE.tmp" "$BASELINE_FILE"

echo "Baseline updated: containers=$(echo "$DOCKER_JSON" | jq 'length') network_ports=$(echo "$NETWORK_PORTS_JSON" | jq 'length')"
echo "Verify with: spectre run security/baseline/run (or drift-detection helper) using SECURITY_BASELINE_FILE=$BASELINE_FILE"
