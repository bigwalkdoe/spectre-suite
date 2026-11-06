#!/bin/bash
# Consolidation (§2.2): canonical implementation lives in scripts/performance/check-performance.sh
# (scheduled by systemd). This path is kept as a delegator to collapse the duplicate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../performance/check-performance.sh" "$@"