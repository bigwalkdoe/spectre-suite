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
INCLUDES=()
EXPECT=""
set -- "${@:-}"
while [ "${1+x}" = x ]; do
  arg="$1"; shift || true
  if [ -n "$EXPECT" ]; then
    case "$EXPECT" in
      snapshot) SNAPSHOT="$arg" ;;
      target) TARGET="$arg" ;;
      include) INCLUDES+=("$arg") ;;
    esac
    EXPECT=""; continue
  fi
  case "$arg" in
    --list|--snapshots) JUST_LIST=true ;;
    --snapshot=*) SNAPSHOT="${arg#*=}" ;;
    --snapshot) EXPECT=snapshot ;;
    --dry-run) DRY_RUN=true ;;
    --local) USE_LOCAL=true ;;
    --target=*) TARGET="${arg#*=}" ;;
    --target) EXPECT=target ;;
    --include=*) INCLUDES+=("${arg#*=}") ;;
    --include) EXPECT=include ;;
    --help|-h)
      cat <<EOF
Usage: $(basename "$0") [--list] [--snapshot <id>] [--dry-run] [--target <dir>] [--local] [--include <path>|path ...]
Extra path arguments (or --include=<path>) limit restore to matching paths.
EOF
      exit 0 ;;
    *) INCLUDES+=("$arg") ;;
  esac
done
[ -n "$EXPECT" ] && { echo "missing value for --$EXPECT" >&2; exit 2; }

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
for inc in ${INCLUDES[@]+"${INCLUDES[@]}"}; do args+=(--include "$inc"); done
restic "${args[@]}"
