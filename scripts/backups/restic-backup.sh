#!/bin/bash
# Restic backup of existing spectre-suite backup artifacts (default strategy A).
#
# Backs up local backup artifacts (same scope as replicate-backups.sh manifest)
# into a restic repository. Keeps current backup producers and
# check-backup-health.sh semantics intact.
#
# Required (unless --init-only with RESTIC_REPOSITORY set appropriately):
#   RESTIC_REPOSITORY      repo path/URL (default: /backups/spectre-backup)
#   RESTIC_PASSWORD or RESTIC_PASSWORD_FILE
#
# Optional:
#   RESTIC_CONFIG          env file to source (default: ~//.secrets/backup-config.env)
#   BACKUP_ROOT            default: /backups
#   PROJECT_PREFIX         default: spectre-suite
#   RESTIC_TAG             default: spectre-suite
#   RESTIC_HOST            --host for restic (default: system hostname)
#   RESTIC_EXTRA_ARGS      extra args passed to `restic backup` (space-split; avoid secrets)
#   RESTIC_INCLUDE_CONFIGS set to 1 to include /backups/configurations and /backups/projects
#
# Usage:
#   restic-backup.sh [--init] [--dry-run]
#   restic-backup.sh --check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

RESTIC_CONFIG="${RESTIC_CONFIG:-~//.secrets/backup-config.env}"
BACKUP_ROOT="${BACKUP_ROOT:-/backups}"
PROJECT_PREFIX="${PROJECT_PREFIX:-spectre-suite}"
RESTIC_TAG="${RESTIC_TAG:-spectre-suite}"
RESTIC_HOST="${RESTIC_HOST:-$(hostname -s)}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"
LOG_DIR="${LOG_DIR:-$PROJECT_ROOT/../logs}"
DO_INIT=0
DO_CHECK=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage: restic-backup.sh [--init] [--dry-run] [--check]
  --init     initialize repository if missing (restic init)
  --check    run `restic check` (no backup)
  --dry-run  pass --dry-run to restic backup
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --init) DO_INIT=1 ;;
    --check) DO_CHECK=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/restic-backup.log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"; }

if [ -f "$RESTIC_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$RESTIC_CONFIG"
fi

# Re-apply defaults after config sourcing (config may set RESTIC_REPOSITORY etc.)
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"
export RESTIC_REPOSITORY

if ! command -v restic >/dev/null 2>&1; then
  log "FAIL: restic not installed"
  exit 1
fi
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
  log "FAIL: set RESTIC_PASSWORD or RESTIC_PASSWORD_FILE (do not put secrets in this repo)"
  exit 1
fi

if [ "$DO_INIT" -eq 1 ]; then
  if restic snapshots >/dev/null 2>&1; then
    log "repo already initialized: $RESTIC_REPOSITORY"
  else
    log "initializing restic repository: $RESTIC_REPOSITORY"
    restic init
  fi
fi

if [ "$DO_CHECK" -eq 1 ]; then
  log "running restic check"
  restic check
  log "OK: restic check"
  exit 0
fi

# Build source list from existing artifacts (manifest-aligned with replicate-backups.sh).
sources=()
shopt -s nullglob
for f in "$BACKUP_ROOT"/databases/postgres_*.sql.gz "$BACKUP_ROOT"/databases/redis_backup_*.rdb; do
  [ -e "$f" ] && sources+=("$f")
done
for f in "$BACKUP_ROOT"/docker-volumes/"${PROJECT_PREFIX}"_*.tar.gz; do
  [ -e "$f" ] && sources+=("$f")
done
if [ "${RESTIC_INCLUDE_CONFIGS:-0}" = "1" ]; then
  [ -d "$BACKUP_ROOT/configurations" ] && sources+=("$BACKUP_ROOT/configurations")
  [ -d "$BACKUP_ROOT/projects" ] && sources+=("$BACKUP_ROOT/projects")
fi
shopt -u nullglob

if [ "${#sources[@]}" -eq 0 ]; then
  log "FAIL: no backup artifacts found under $BACKUP_ROOT (run local backups first)"
  exit 1
fi

log "starting restic backup: ${#sources[@]} source(s) -> $RESTIC_REPOSITORY (tag=$RESTIC_TAG host=$RESTIC_HOST)"
args=(backup --tag "$RESTIC_TAG" --host "$RESTIC_HOST")
[ "$DRY_RUN" -eq 1 ] && args+=(--dry-run)
if [ -n "${RESTIC_EXTRA_ARGS:-}" ]; then
  # shellcheck disable=SC2206
  extra=( $RESTIC_EXTRA_ARGS )
  args+=("${extra[@]}")
fi
args+=("${sources[@]}")

restic "${args[@]}"
log "OK: restic backup completed"
