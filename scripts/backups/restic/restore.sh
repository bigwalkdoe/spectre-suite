#!/bin/bash
# Restic restore for spectre-suite (defaults to local repo).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

JUST_LIST=false
SNAPSHOT="latest"
DRY_RUN=false
USE_LOCAL=false
TARGET=""
for arg in "${@:-}"; do
  case "$arg" in
    --list|--snapshots) JUST_LIST=true ;;
    --snapshot=*) SNAPSHOT="${arg#*=}" ;;
    --snapshot) SNAPSHOT="next" ;;
    --dry-run) DRY_RUN=true ;;
    --local) USE_LOCAL=true ;;
    --target=*) TARGET="${arg#*=}" ;;
    --target) TARGET="next" ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--list] [--snapshot <id>] [--dry-run] [--target <dir>] [--local]
EOF
      exit 0 ;;
    *)
      if [ "$SNAPSHOT" = "next" ]; then SNAPSHOT="$arg";
      elif [ "$TARGET" = "next" ]; then TARGET="$arg"; fi ;;
  esac
done
[ "$SNAPSHOT" = "next" ] && SNAPSHOT="latest"
[ "$TARGET" = "next" ] && TARGET=""

resolve_restic_dirs
load_restic_env || true
RESTIC_REPOSITORY_LOCAL="${RESTIC_REPOSITORY_LOCAL:-/backups/spectre-backup}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:spectre-backup:}"
[ -n "${RESTIC_PASSWORD_FILE:-}" ] && [ -f "$RESTIC_PASSWORD_FILE" ] && export RESTIC_PASSWORD_FILE

# default to local repo
repo="$RESTIC_REPOSITORY_LOCAL"
[ -z "$repo" ] && repo="$RESTIC_REPOSITORY"
[ "$USE_LOCAL" = true ] && repo="$RESTIC_REPOSITORY_LOCAL"

if [ "$JUST_LIST" = true ]; then
  restic -r "$repo" snapshots
  exit 0
fi

args=(-r "$repo" restore "$SNAPSHOT")
[ -n "$TARGET" ] && args+=(--target "$TARGET")
[ "$DRY_RUN" = true ] && args+=(--dry-run)
restic "${args[@]}"
