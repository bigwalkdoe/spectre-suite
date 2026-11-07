#!/bin/bash
# Forwarder (§8.4 pattern): delegate to spectre/monitoring exporter implementation.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_REPO_ROOT="$(cd "$_SELF_DIR" && while [ ! -d spectre/actions ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"
export SPECTRE_REPO_ROOT
_TARGET="$SPECTRE_REPO_ROOT/spectre/monitoring/exporters/security-baseline-metrics-exporter.sh"
# shellcheck source=/dev/null
if [ "${BASH_SOURCE[0]-$0}" = "${0-}" ]; then exec "$_TARGET" "$@"; else . "$_TARGET"; fi
