#!/bin/bash
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$_SELF_DIR/opa-compat-report.py" "$@"
