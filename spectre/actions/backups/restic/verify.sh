#!/bin/bash
# Restic repository verification for spectre-suite; writes last-verify marker.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

FULL=false
USE_LOCAL=false
for arg in "${@:-}"; do
  case "$arg" in
    --full|--check-data) FULL=true ;;
    --local) USE_LOCAL=true ;;
    --help|-h) echo "Usage: $(basename "$0") [--full] [--local]"; exit 0 ;;
  esac
done

resolve_restic_dirs
load_restic_env || true
RESTIC_REPOSITORY_LOCAL="${RESTIC_REPOSITORY_LOCAL:-/backups/spectre-backup}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:spectre-backup:}"
[ -n "${RESTIC_PASSWORD_FILE:-}" ] && [ -f "$RESTIC_PASSWORD_FILE" ] && export RESTIC_PASSWORD_FILE

repo="$RESTIC_REPOSITORY"
if [ "$USE_LOCAL" = true ] || [ -n "${RESTIC_REPOSITORY_LOCAL:-}" ]; then
  repo="${RESTIC_REPOSITORY_LOCAL:-$repo}"
fi
[ "$USE_LOCAL" = true ] && repo="$RESTIC_REPOSITORY_LOCAL"

ok=1
if [ "$FULL" = true ]; then
  restic -r "$repo" check --read-data-subset=5% || ok=0
else
  restic -r "$repo" check || ok=0
fi
write_marker last-verify "$ok" "$(date +%s)"
[ "$ok" -eq 1 ] || exit 1
info "Verify OK: $repo"
