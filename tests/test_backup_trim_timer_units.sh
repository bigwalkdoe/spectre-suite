#!/bin/bash
# Test scheduled local backup artifact trimming timer installer and repo-managed units.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

INSTALLER="$PROJECT_ROOT/spectre/actions/systemd/install-backup-trim-timer.sh"
SVC="$PROJECT_ROOT/systemd/backup-trim.service"
TMR="$PROJECT_ROOT/systemd/backup-trim.timer"

# installer --print contract
[ -x "$INSTALLER" ] || fail "backup trim timer installer missing or not executable: $INSTALLER"
out=$("$INSTALLER" --print)
printf '%s' "$out" | grep -Eq 'spectre run backups/trim-backup-artifacts|backups/trim-backup-artifacts' || fail "backup trim timer must dispatch backups/trim-backup-artifacts"
printf '%s' "$out" | grep -q 'OnCalendar=' || fail "backup trim timer must include OnCalendar"
printf '%s' "$out" | grep -q '05:45:00' || fail "backup trim timer default OnCalendar must be daily 05:45:00"
printf '%s' "$out" | grep -q 'Persistent=true' || fail "backup trim timer must be Persistent"
printf '%s' "$out" | grep -q 'backup-trim.timer' || fail "backup trim timer unit name present"
pass "install-backup-trim-timer.sh --print targets backups/trim-backup-artifacts"

# repo-managed unit files
[ -f "$TMR" ] || fail "repo timer unit missing: $TMR"
[ -f "$SVC" ] || fail "repo service unit missing: $SVC"
grep -q 'OnCalendar=.*05:45:00' "$TMR" || fail "repo timer must have daily 05:45:00 cadence"
grep -q 'Persistent=true' "$TMR" || fail "repo timer must set Persistent=true"
grep -Eq 'spectre run backups/trim-backup-artifacts|backups/trim-backup-artifacts' "$SVC" || fail "repo service must ExecStart trim-backup-artifacts action"
pass "repo backup-trim units present with expected cadence/intent"

# registry entry
python3 - "$PROJECT_ROOT/spectre/dispatch/registry_data.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
entries = [e for e in data if e.get('name') == 'backups/trim-backup-artifacts']
assert entries, 'registry missing backups/trim-backup-artifacts'
e = entries[0]
assert e.get('mutates') is True, 'must be mutating'
assert e.get('concurrency') in ('forbid', 'serial', '1', 1, 'queue'), f'unexpected concurrency: {e.get("concurrency")!r}'
print('registry ok')
PY
pass "registry entry for backups/trim-backup-artifacts present"

echo "All backup trim timer unit tests passed."
