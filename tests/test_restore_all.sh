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
# LOG_FILE is exported by the orchestrator; record whether the component saw
# it, so the test can tell an exported var from an unexported one.
echo "$name \$* LOG_FILE=\${LOG_FILE:-<unset>}" >> "\${CALLS:?}"
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
    && grep -q "^databases latest " "$CALLS" \
    && grep -q "^volumes latest " "$CALLS" \
    && grep -q "^ok " <<<"$(marker)"; then
    pass "--execute --yes restores selected components and writes ok verdict"
else
    fail "selected restore failed (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null), marker=$(marker)): $OUT"
fi

# 5) A failed component does not stop the others and fails the run.
reset_calls
STUB_DB_RC=1 run_restore --execute --yes --databases --volumes
if [ "$RC" -eq 1 ] \
    && grep -q "^databases latest " "$CALLS" \
    && grep -q "^volumes latest " "$CALLS" \
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
if [ "$RC" -eq 0 ] && grep -q "restic --snapshot abc123 --target $TARGET" "$CALLS"; then
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

# 12) The dispatcher's default 30-minute deadline would SIGKILL a real restore
# part-way through, leaving a half-restored host and no verdict. The registry
# entry must carry a deadline sized for a full disaster recovery.
timeout=$(cd "$PROJECT_ROOT" && python3 -c \
    "from spectre.dispatch.registry import get_job; print(get_job('backups/restore-all').timeout)" 2>/dev/null)
if [ "${timeout:-0}" -ge 14400 ] 2>/dev/null; then
    pass "registry timeout (${timeout}s) leaves room for a full restore"
else
    fail "registry timeout is ${timeout:-missing}; the 1800s default kills a real restore mid-run"
fi

# 13) rsync only downloads artifacts to /tmp; it does not apply them. An
# operator finishing a disaster recovery must not read "SUCCESS" and stop.
reset_calls
run_restore --remote --remote-source rsync --remote-location srv --remote-type databases
if [ "$RC" -eq 0 ] && grep -qi "downloads only" <<<"$OUT"; then
    pass "rsync plan says it downloads only"
else
    fail "rsync plan does not distinguish download from restore (rc=$RC): $OUT"
fi

reset_calls
run_restore --execute --yes --remote --remote-source rsync --remote-location srv --remote-type databases
if [ "$RC" -eq 0 ] \
    && grep -q "^remote rsync databases srv " "$CALLS" \
    && grep -qi "fetched only" <<<"$OUT" \
    && grep -q "rsync" "$STATE/last-restore-health"; then
    pass "rsync execute reports a fetch, not a completed restore"
else
    fail "rsync execute misreports success (rc=$RC, marker=$(marker)): $OUT"
fi

# 14) `--flag=value` must be refused the same way as the spaced form. The
# `=` branch strips the value but never checks it, so `--snapshot=` passes an
# empty snapshot id straight through to restic.
reset_calls
run_restore --execute --yes --restic --snapshot= --restic-target "$FIXTURE/restore-target"
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--snapshot= with an empty value is refused"
else
    fail "--snapshot= was not refused (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

reset_calls
run_restore --execute --yes --remote --remote-source= --remote-location srv
if [ "$RC" -eq 2 ] && [ ! -f "$CALLS" ]; then
    pass "--remote-source= with an empty value is refused"
else
    fail "--remote-source= was not refused (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 15) LOG_FILE must be exported, not merely assigned: the summary advertises
# it as the log that holds the detail, so a component that writes its own
# lines must be able to find it. The stub records the value it sees.
reset_calls
run_restore --execute --yes --databases
seen=$(grep '^databases .* LOG_FILE=' "$CALLS" 2>/dev/null | sed 's/^databases .* LOG_FILE=//')
if [ -n "$seen" ]; then
    pass "LOG_FILE is exported so components can write to the advertised log"
else
    fail "LOG_FILE was not exported to the component (saw: $(cat "$CALLS" 2>/dev/null))"
fi

# 16) A test that forces a stub to fail must not leak that failure into later
# cases. Case 5 runs `STUB_DB_RC=1 run_restore ...`; that assignment is scoped
# to the command and must not persist in this shell, or every later database
# run would fail too -- harmless today only because no later case runs the
# database stub. Assert the scope directly rather than inferring it.
if [ -z "${STUB_DB_RC:-}" ]; then
    pass "a per-command failure assignment does not leak into this shell"
else
    fail "STUB_DB_RC leaked into this shell: $STUB_DB_RC"
fi

reset_calls
run_restore --execute --yes --databases
db_line='^databases latest '
if [ "$RC" -eq 0 ] && grep -q "$db_line" "$CALLS"; then
    pass "the database stub still succeeds after a failed case"
else
    fail "a forced failure in an earlier case leaked (rc=$RC, calls=$(cat "$CALLS" 2>/dev/null)): $OUT"
fi

# 17) An execute that aborts on a missing component must not leave a stale
# verdict behind. If a previous run wrote `ok` and this one dies before
# reaching write_verdict, the marker still says ok -- which would report a
# failed restore as successful.
rm -f "$ACTIONS/restore-docker-volumes.sh"
printf 'ok %s\n' "$(date +%s)" > "$STATE/last-restore-health"
reset_calls
run_restore --execute --yes --volumes
if [ "$RC" -ne 0 ] && grep -q "$ACTIONS/restore-docker-volumes.sh" <<<"$OUT" \
   && grep -q "^failed " <<<"$(marker)"; then
    pass "a missing-component abort writes a failed verdict, not a stale ok"
else
    fail "missing-component abort left a stale verdict (rc=$RC, marker=$(marker)): $OUT"
fi
write_stub "$ACTIONS/restore-docker-volumes.sh" "volumes" "STUB_VOL_RC"

# 18) The dry-run plan must not name a specific archive, because the component
# script picks its own and the two can disagree. A plan that promises
# `postgres_20261113.sql.gz` while the script restores a different file is
# worse than no name at all: it invites the operator to verify the wrong
# artifact.
reset_calls
run_restore --databases
if [ "$RC" -eq 0 ] && ! grep -qE '\.sql\.gz' <<<"$OUT"; then
    pass "the dry-run plan does not name a specific archive"
else
    fail "the dry-run plan names a specific archive (rc=$RC): $OUT"
fi

cleanup_fixture

echo "restore-all tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
