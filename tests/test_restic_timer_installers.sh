#!/bin/bash
# Test adopted restic timer installers (print/uninstall contract). Protects catch-up.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

backup_out=$("$PROJECT_ROOT/spectre/actions/systemd/install-restic-timer.sh" --print)
printf '%s' "$backup_out" | grep -q '04:10:00' || fail "backup timer must run at 04:10:00"
printf '%s' "$backup_out" | grep -Eq 'spectre run backups/restic/backup|backups/restic/backup' || fail "backup timer must dispatch backups/restic/backup"
printf '%s' "$backup_out" | grep -q 'spectre-suite-backups.env' || fail "backup timer must default to spectre-suite-backups.env"
printf '%s' "$backup_out" | grep -q 'Persistent=true' || fail "backup timer must be Persistent"
printf '%s' "$backup_out" | grep -qv 'spectre-backup-catchup' || fail "must not reference catch-up timer"
pass "install-restic-timer.sh --print targets adopted backup"

verify_out=$("$PROJECT_ROOT/spectre/actions/systemd/install-restic-verify-timer.sh" --print)
printf '%s' "$verify_out" | grep -Eq 'spectre run backups/restic/verify|backups/restic/verify' || fail "verify timer must dispatch backups/restic/verify"
printf '%s' "$verify_out" | grep -q 'spectre-restic-verify.timer' || fail "verify timer unit name"
printf '%s' "$verify_out" | grep -q 'Persistent=true' || fail "verify timer must be Persistent"
printf '%s' "$verify_out" | grep -qv 'spectre-backup-catchup' || fail "must not reference catch-up timer"
pass "install-restic-verify-timer.sh --print targets adopted verify"

# retired files must be gone
for f in \
  scripts/backups/restic-backup.sh \
  scripts/backups/restic-maintenance.sh \
  scripts/backups/restic-forget-prune.sh \
  scripts/backups/restic.env.example \
  scripts/systemd/install-restic-maintenance-timer.sh; do
  [ ! -e "$PROJECT_ROOT/$f" ] || fail "retired file still exists: $f"
done
pass "retired suite restic stubs removed"

# catch-up must remain
{ [ -f "$PROJECT_ROOT/spectre/actions/backups/run-missed-backups.sh" ] || [ -f "$PROJECT_ROOT/scripts/backups/run-missed-backups.sh" ]; } || fail "catch-up action missing"
{ [ -f "$PROJECT_ROOT/spectre/actions/systemd/install-backup-catchup-timer.sh" ] || [ -f "$PROJECT_ROOT/scripts/systemd/install-backup-catchup-timer.sh" ]; } || fail "catch-up timer installer missing"
pass "spectre-backup-catchup assets preserved"
