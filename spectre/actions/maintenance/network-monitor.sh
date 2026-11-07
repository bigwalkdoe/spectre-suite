#!/bin/bash
# Consolidation (§2.2): canonical implementation lives in spectre/actions/network/monitor-network.sh
# (referenced by docs/runbooks). This path is kept as a compatibility delegator to collapse the duplicate.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../network/monitor-network.sh" "$@"