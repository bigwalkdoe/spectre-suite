#!/bin/bash
# Test scheduled restic prune timer installer and repo-managed units.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

INSTALLER="$PROJECT_ROOT/spectre/actions/systemd/install-restic-prune-timer.sh"
SVC="$PROJECT_ROOT/systemd/spectre-restic-prune.service"
TMR="$PROJECT_ROOT/systemd/spectre-restic-prune.timer"

# installer --print contract
[ -x "$INSTALLER" ] || fail "prune timer installer missing or not executable: $INSTALLER"
out=$("$INSTALLER" --print)
printf '%s' "$out" | grep -Eq 'spectre run backups/restic/prune|backups/restic/prune' || fail "prune timer must dispatch backups/restic/prune"
printf '%s' "$out" | grep -q 'OnCalendar=' || fail "prune timer must include OnCalendar"
printf '%s' "$out" | grep -q '05:30:00' || fail "prune timer default OnCalendar must be daily 05:30:00"
printf '%s' "$out" | grep -q 'Persistent=true' || fail "prune timer must be Persistent"
printf '%s' "$out" | grep -q 'spectre-restic-prune.timer' || fail "prune timer unit name present"
printf '%s' "$out" | grep -qv 'spectre-backup-catchup' || fail "must not reference catch-up timer"
pass "install-restic-prune-timer.sh --print targets tag-scoped prune"

# repo-managed unit files
[ -f "$TMR" ] || fail "repo timer unit missing: $TMR"
[ -f "$SVC" ] || fail "repo service unit missing: $SVC"
grep -q 'OnCalendar=.*05:30:00' "$TMR" || fail "repo timer must have daily 05:30:00 cadence"
grep -q 'Persistent=true' "$TMR" || fail "repo timer must set Persistent=true"
grep -Eq 'spectre run backups/restic/prune|backups/restic/prune' "$SVC" || fail "repo service must ExecStart prune action"
pass "repo spectre-restic-prune units present with expected cadence/intent"

echo "All restic prune timer unit tests passed."
