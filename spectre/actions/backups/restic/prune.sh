#!/bin/bash
# Tag-scoped restic forget/prune for spectre-suite. Never forgets without --tag.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

DRY_RUN=false
REPO_MODE="all"
for arg in "${@:-}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --repo) REPO_MODE="next" ;;
    --repo=*) REPO_MODE="${arg#*=}" ;;
    local|offsite|all) [ "$REPO_MODE" = "next" ] && REPO_MODE="$arg" ;;
    --help|-h) echo "Usage: $(basename "$0") [--dry-run] [--repo local|offsite|all]"; exit 0 ;;
  esac
done

resolve_restic_dirs
load_restic_env || true
RESTIC_REPOSITORY_LOCAL="${RESTIC_REPOSITORY_LOCAL:-/backups/spectre-backup}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-rclone:spectre-backup:}"
[ -n "${RESTIC_PASSWORD_FILE:-}" ] && [ -f "$RESTIC_PASSWORD_FILE" ] && export RESTIC_PASSWORD_FILE

# shellcheck disable=SC2046
args=(forget $(restic_forget_args) --prune)
[ "$DRY_RUN" = true ] && args+=(--dry-run)

run_one() {
  local repo="$1" label="$2"
  [ -z "$repo" ] && return 0
  info "[$label] restic ${args[*]} -r $repo"
  restic -r "$repo" "${args[@]}"
}

case "$REPO_MODE" in
  local) run_one "$RESTIC_REPOSITORY_LOCAL" local ;;
  offsite) run_one "$RESTIC_REPOSITORY" offsite ;;
  all)
    [ -n "${RESTIC_REPOSITORY_LOCAL:-}" ] && run_one "$RESTIC_REPOSITORY_LOCAL" local
    [ -n "${RESTIC_REPOSITORY:-}" ] && [ "$DRY_RUN" = true -o -n "${RESTIC_REPOSITORY_LOCAL:-}" ] && run_one "$RESTIC_REPOSITORY" offsite || true
    ;;
  *) error "unknown --repo: $REPO_MODE"; exit 2 ;;
esac
