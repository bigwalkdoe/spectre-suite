#!/bin/bash
# Forwarder: set repo root, delegate to spectre/monitoring impl.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_REPO_ROOT="$(cd "$_SELF_DIR" && while [ ! -d spectre/actions ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"
export SPECTRE_REPO_ROOT
_TARGET="$SPECTRE_REPO_ROOT/spectre/monitoring/exporters/monitoring-stack-metrics-exporter.sh"
# shellcheck disable=SC1090
if [ "${BASH_SOURCE[0]-$0}" = "${0-}" ]; then exec "$_TARGET" "$@"; else . "$_TARGET"; fi
