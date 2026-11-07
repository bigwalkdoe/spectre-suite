#!/bin/bash
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$_SELF_DIR/check-file-integrity-local.sh" "$@"
