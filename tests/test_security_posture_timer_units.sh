#!/bin/bash
# Test scheduled security posture maintenance timer installer and repo-managed units.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
pass() { echo "✅ $1"; }
fail() { echo "❌ $1"; exit 1; }

INSTALLER="$PROJECT_ROOT/spectre/actions/systemd/install-security-posture-maintenance-timer.sh"
SVC="$PROJECT_ROOT/systemd/security-posture-maintenance.service"
TMR="$PROJECT_ROOT/systemd/security-posture-maintenance.timer"

# installer --print contract
[ -x "$INSTALLER" ] || fail "security posture maintenance timer installer missing or not executable: $INSTALLER"
out=$("$INSTALLER" --print)
printf '%s' "$out" | grep -Eq 'spectre run security/security-posture-maintenance|security/security-posture-maintenance' || fail "posture timer must dispatch security/security-posture-maintenance"
printf '%s' "$out" | grep -q 'OnCalendar=' || fail "posture timer must include OnCalendar"
printf '%s' "$out" | grep -Eq 'OnCalendar=.*(\*:0/15|\*/15)' || fail "posture timer default OnCalendar must run every 15 minutes"
printf '%s' "$out" | grep -q 'Persistent=true' || fail "posture timer must be Persistent"
printf '%s' "$out" | grep -q 'security-posture-maintenance.timer' || fail "posture timer unit name present"
pass "install-security-posture-maintenance-timer.sh --print targets security/security-posture-maintenance"

# repo-managed unit files
[ -f "$TMR" ] || fail "repo timer unit missing: $TMR"
[ -f "$SVC" ] || fail "repo service unit missing: $SVC"
grep -Eq 'OnCalendar=.*(\*:0/15|\*/15)' "$TMR" || fail "repo timer must have 15-minute cadence"
grep -q 'Persistent=true' "$TMR" || fail "repo timer must set Persistent=true"
grep -Eq 'spectre run security/security-posture-maintenance|security/security-posture-maintenance' "$SVC" || fail "repo service must ExecStart posture maintenance action"
pass "repo security-posture-maintenance units present with expected cadence/intent"

# registry entry
python3 - "$PROJECT_ROOT/spectre/dispatch/registry_data.json" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    data = json.load(f)
entries = [e for e in data if e.get('name') == 'security/security-posture-maintenance']
assert entries, 'registry missing security/security-posture-maintenance'
e = entries[0]
assert e.get('mutates') is True, 'must be mutating'
assert e.get('concurrency') in ('forbid', 'serial', '1', 1, 'queue'), f'unexpected concurrency: {e.get("concurrency")!r}'
print('registry ok')
PY
pass "registry entry for security/security-posture-maintenance present"

echo "All security posture maintenance timer unit tests passed."
