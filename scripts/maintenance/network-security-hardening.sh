#!/bin/bash
# Consolidation (§2.2): canonical (documented) implementation lives in
# scripts/network/harden-network-security.sh. This path is kept as a delegator to
# collapse the duplicate. (The previous aggressive variant reset firewalls/SSH and
# was unreferenced by docs/schedulers; prefer the documented hardening entrypoint.)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/../network/harden-network-security.sh" "$@"