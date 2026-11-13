#!/bin/bash
# backups/restore-all operator-orchestrator tests.
#
# No real backup paths or Docker/PostgreSQL calls: sibling restore scripts are
# stubs in a temp RESTORE_ACTION_DIR that record their argv.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RESTORE_ALL="$PROJECT_ROOT/spectre/actions/backups/restore-all.sh"

echo "Running restore-all orchestrator tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$RESTORE_ALL" ]; then
    echo "❌ restore-all.sh does not exist"
    exit 1
fi

setup_fixture() {
    FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/restore-all-test.XXXXXX")
    ACTIONS="$FIXTURE/actions"
    STATE="$FIXTURE/state"
    CALLS="$FIXTURE/calls.log"
    LOG="$FIXTURE/restore.log"
    mkdir -p "$ACTIONS/restic" "$STATE" "$FIXTURE/databases" "$FIXTURE/volumes"
    write_stub "$ACTIONS/restore-databases.sh" "databases" "STUB_DB_RC"
    write_stub "$ACTIONS/restore-docker-volumes.sh" "volumes" "STUB_VOL_RC"
    write_stub "$ACTIONS/restic/restore.sh" "restic" "STUB_RESTIC_RC"
    write_stub "$ACTIONS/restore-from-remote.sh" "remote" "STUB_REMOTE_RC"
}

write_stub() {
    local path="$1" name="$2" rcvar="$3"
    cat > "$path" <<EOF
#!/bin/bash
echo "$name \$*" >> "\${CALLS:?}"
exit "\${$rcvar:-0}"
EOF
    chmod +x "$path"
}

cleanup_fixture() {
    rm -rf "$FIXTURE"
}

run_restore() {
    OUT=$(RESTORE_ACTION_DIR="$ACTIONS" \
        BACKUP_STATE_DIR="$STATE" \
        BACKUP_DIR="$FIXTURE/databases" \
        VOLUME_BACKUP_DIR="$FIXTURE/volumes" \
        LOG_FILE="$LOG" \
        CALLS="$CALLS" \
        STUB_DB_RC="${STUB_DB_RC:-0}" \
        STUB_VOL_RC="${STUB_VOL_RC:-0}" \
        STUB_RESTIC_RC="${STUB_RESTIC_RC:-0}" \
        STUB_REMOTE_RC="${STUB_REMOTE_RC:-0}" \
        "$RESTORE_ALL" "$@" 2>&1) && RC=0 || RC=$?
}

reset_calls() {
    rm -f "$CALLS" "$STATE/last-restore-health"
}

marker() {
    cat "$STATE/last-restore-health" 2>/dev/null || true
}

# 1) --help exits 0 and states the safe default.
setup_fixture
run_restore --help
if [ "$RC" -eq 0 ] && grep -q "Default: --dry-run" <<<"$OUT"; then
    pass "--help documents the dry-run default"
else
    fail "--help missing or wrong (rc=$RC): $OUT"
fi

# 2) Default is a dry run: no sibling runs, no marker.
reset_calls
run_restore
if [ "$RC" -eq 0 ] && grep -q "DRY RUN" <<<"$OUT" && [ ! -f "$CALLS" ] && [ ! -f "$STATE/last-restore-health" ]; then
    pass "default dry-run performs no restore and writes no marker"
else
    fail "default dry-run mutated state (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null), marker=$(marker)): $OUT"
fi

# 3) --execute without --yes is refused before anything runs.
reset_calls
run_restore --execute --databases
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--execute without --yes exits 2 and runs nothing"
else
    fail "--execute without --yes was not refused (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 4) --execute --yes runs the selected components and records success.
reset_calls
run_restore --execute --yes --databases --volumes
if [ "$RC" -eq 0 ] \
    && grep -qx "databases latest" "$CALLS" \
    && grep -qx "volumes latest" "$CALLS" \
    && grep -q "^ok " <<<"$(marker)"; then
    pass "--execute --yes restores selected components and writes ok verdict"
else
    fail "selected restore failed (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null), marker=$(marker)): $OUT"
fi

# 5) A failed component does not stop the others and fails the run.
reset_calls
STUB_DB_RC=1 run_restore --execute --yes --databases --volumes
if [ "$RC" -eq 1 ] \
    && grep -qx "databases latest" "$CALLS" \
    && grep -qx "volumes latest" "$CALLS" \
    && grep -q "^failed " <<<"$(marker)"; then
    pass "partial failure continues, exits 1, writes failed verdict"
else
    fail "partial failure handling wrong (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null), marker=$(marker)): $OUT"
fi

# 6) A selected component whose script is missing is a hard error naming it.
rm -f "$ACTIONS/restore-docker-volumes.sh"
reset_calls
run_restore --volumes
if [ "$RC" -ne 0 ] && grep -q "$ACTIONS/restore-docker-volumes.sh" <<<"$OUT"; then
    pass "missing component script exits non-zero and names the path"
else
    fail "missing component script was not reported (rc=$RC): $OUT"
fi
write_stub "$ACTIONS/restore-docker-volumes.sh" "volumes" "STUB_VOL_RC"

# 7) restic restore is refused without an explicit target (no in-place restore).
reset_calls
run_restore --execute --yes --restic
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--restic --execute without --restic-target is refused"
else
    fail "unsafe in-place restic restore was not refused (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 8) restic restore with a target passes snapshot and target through.
reset_calls
TARGET="$FIXTURE/restore-target"
run_restore --execute --yes --restic --snapshot abc123 --restic-target "$TARGET"
if [ "$RC" -eq 0 ] && grep -qx "restic --snapshot abc123 --target $TARGET" "$CALLS"; then
    pass "restic restore passes snapshot and target"
else
    fail "restic args wrong (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 9) Remote restore requires a source and a location.
reset_calls
run_restore --execute --yes --remote
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--remote without source/location is refused"
else
    fail "incomplete remote restore was not refused (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 10) --execute with no component is refused instead of restoring everything.
reset_calls
run_restore --execute --yes
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--execute with no component is refused"
else
    fail "empty component selection ran something (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 11) Unknown flags are usage errors.
reset_calls
run_restore --frobnicate
if [ "$RC" -eq 2 ]; then
    pass "unknown flag exits 2"
else
    fail "unknown flag not refused (rc=$RC): $OUT"
fi

cleanup_fixture

echo "restore-all tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
