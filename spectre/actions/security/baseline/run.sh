#!/bin/bash
# Canonical entrypoint: suite security baseline (delegates to baseline-runner.sh).
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$_SELF_DIR/baseline-runner.sh" "$@"
