#!/bin/bash
# Restic maintenance: snapshots/check/forget/prune (destructive operations require explicit args).
#
# Required:
#   RESTIC_REPOSITORY, RESTIC_PASSWORD or RESTIC_PASSWORD_FILE
# Optional:
#   RESTIC_CONFIG (default: /home/deon/.secrets/backup-config.env)
#
# Usage:
#   restic-maintenance.sh snapshots
#   restic-maintenance.sh check [--read-data-subset=5%]
#   restic-maintenance.sh forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 [--prune] [--dry-run]
#   restic-maintenance.sh prune
set -euo pipefail

RESTIC_CONFIG="${RESTIC_CONFIG:-/home/deon/.secrets/backup-config.env}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"

usage() {
  cat <<'EOF'
Usage: restic-maintenance.sh <snapshots|check|forget|prune> [restic args...]
Examples:
  restic-maintenance.sh snapshots
  restic-maintenance.sh check
  restic-maintenance.sh forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune --dry-run
EOF
}

[ $# -ge 1 ] || { usage; exit 2; }
cmd="$1"; shift
case "$cmd" in -h|--help) usage; exit 0 ;; esac

if [ -f "$RESTIC_CONFIG" ]; then
  # shellcheck disable=SC1090
  . "$RESTIC_CONFIG"
fi
RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/backups/spectre-backup}"
export RESTIC_REPOSITORY

command -v restic >/dev/null 2>&1 || { echo "FAIL: restic not installed" >&2; exit 1; }
if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then
  echo "FAIL: set RESTIC_PASSWORD or RESTIC_PASSWORD_FILE" >&2; exit 1
fi

case "$cmd" in
  snapshots|check|forget|prune|unlock|stats|ls|cat) exec restic "$cmd" "$@" ;;
  *) echo "unknown/unsupported subcommand: $cmd" >&2; usage >&2; exit 2 ;;
esac
