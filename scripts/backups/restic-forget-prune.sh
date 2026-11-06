#!/bin/bash
# Apply restic retention policy (forget + optional prune). Destructive to old
# snapshots per policy - review RESTIC_FORGET_ARGS and run with --dry-run first.
#
# Required: RESTIC_REPOSITORY, RESTIC_PASSWORD or RESTIC_PASSWORD_FILE
# Optional:
#   RESTIC_CONFIG       default: /home/deon/.secrets/backup-config.env
#   RESTIC_FORGET_ARGS  default: --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune
#   RESTIC_DRY_RUN=1    append --dry-run (no changes)
set -euo pipefail

RESTIC_CONFIG="${RESTIC_CONFIG:-/home/deon/.secrets/backup-config.env}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"
RESTIC_FORGET_ARGS="${RESTIC_FORGET_ARGS:---keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune}"

if [ -f "$RESTIC_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$RESTIC_CONFIG"
fi
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"
RESTIC_FORGET_ARGS="${RESTIC_FORGET_ARGS:---keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune}"
export RESTIC_REPOSITORY

command -v restic >/dev/null 2>&1 || { echo "FAIL: restic not installed" >&2; exit 1; }
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ] && [ -z "${RESTIC_PASSWORD_COMMAND:-}" ]; then
  echo "FAIL: set RESTIC_PASSWORD, RESTIC_PASSWORD_FILE, or RESTIC_PASSWORD_COMMAND" >&2; exit 1
fi

# shellcheck disable=SC2206
args=(forget $RESTIC_FORGET_ARGS)
[ "${RESTIC_DRY_RUN:-0}" = "1" ] && args+=(--dry-run)
echo "[$(date '+%Y-%m-%d %H:%M:%S')] restic ${args[*]} (repo=$RESTIC_REPOSITORY)"
exec restic "${args[@]}"
