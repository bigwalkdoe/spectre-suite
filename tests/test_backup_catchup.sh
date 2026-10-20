#!/bin/bash
# Backup catch-up timer tests
#
# The daily database backup runs at 01:00 from cron. A workstation that is
# asleep then misses the run, and cron does not catch up. The catch-up timer
# exists to notice that on wake and run the backup only when it is actually
# stale. These tests cover that decision, the lock that prevents two catch-up
# runs from overlapping, and the unit the installer generates.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
WRAPPER="$PROJECT_ROOT/scripts/backups/run-missed-backups.sh"
INSTALLER="$PROJECT_ROOT/scripts/systemd/install-backup-catchup-timer.sh"

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/spectre-catchup-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

# The wrapper resolves check-backup-health.sh and backup-all.sh relative to its
# own directory. Copying it into a sandbox lets the test exercise the real
# control flow without touching the real backup directory or Docker.
make_sandbox() {
    local root="$1"
    mkdir -p "$root/scripts/backups" "$root/bin" "$root/run" "$root/home" "$root/state"
    cp "$WRAPPER" "$root/scripts/backups/run-missed-backups.sh"
    chmod +x "$root/scripts/backups/run-missed-backups.sh"

    cat > "$root/bin/docker" <<'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$root/bin/docker"

    cat > "$root/scripts/backups/check-backup-health.sh" <<'EOF'
#!/bin/bash
echo health >> "${TEST_HEALTH_LOG:?}"
mode="${TEST_HEALTH_MODE:-healthy}"
if [ "$mode" = "healthy" ]; then
    exit 0
fi
if [ "$mode" = "becomes-healthy" ] && [ -f "${TEST_BACKUP_MARKER:?}" ]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$root/scripts/backups/check-backup-health.sh"

    cat > "$root/scripts/backups/backup-all.sh" <<'EOF'
#!/bin/bash
echo backup >> "${TEST_BACKUP_LOG:?}"
touch "${TEST_BACKUP_MARKER:?}"
exit "${TEST_BACKUP_EXIT:-0}"
EOF
    chmod +x "$root/scripts/backups/backup-all.sh"
}

# --- installer output --------------------------------------------------------
if [ ! -x "$INSTALLER" ]; then
    fail "missing or non-executable installer: scripts/systemd/install-backup-catchup-timer.sh"
else
    installer_output=$("$INSTALLER" --print 2>&1)
    installer_status=$?
    if [ "$installer_status" -ne 0 ]; then
        fail "installer --print exited $installer_status"
    elif ! printf '%s\n' "$installer_output" | grep -q 'OnCalendar=.*05:00:00'; then
        fail "installer timer does not run at 05:00"
    elif ! printf '%s\n' "$installer_output" | grep -q '^Persistent=true$'; then
        fail "installer timer is not persistent"
    elif ! printf '%s\n' "$installer_output" | grep -Fq "ExecStart=$PROJECT_ROOT/scripts/backups/run-missed-backups.sh"; then
        fail "installer service does not run this repository's catch-up wrapper"
    else
        pass "installer emits a persistent 05:00 timer for the catch-up wrapper"
    fi
fi

# --- wrapper decisions -------------------------------------------------------
if [ ! -x "$WRAPPER" ]; then
    fail "missing or non-executable wrapper: scripts/backups/run-missed-backups.sh"
else
    # Healthy backups: the wrapper must be a no-op.
    sandbox="$TMP_ROOT/healthy"
    make_sandbox "$sandbox"
    out="$TMP_ROOT/healthy.out"
    TEST_HEALTH_MODE=healthy \
    TEST_HEALTH_LOG="$TMP_ROOT/healthy.health" \
    TEST_BACKUP_LOG="$TMP_ROOT/healthy.backup" \
    TEST_BACKUP_MARKER="$TMP_ROOT/healthy.marker" \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/run" XDG_STATE_HOME="$sandbox/state" \
    PATH="$sandbox/bin:$PATH" \
        "$sandbox/scripts/backups/run-missed-backups.sh" >"$out" 2>&1
    healthy_status=$?
    if [ "$healthy_status" -ne 0 ]; then
        fail "healthy path exited $healthy_status"
    elif [ ! -f "$TMP_ROOT/healthy.health" ]; then
        fail "healthy path did not run the health check"
    elif [ -f "$TMP_ROOT/healthy.backup" ]; then
        fail "healthy path ran a backup when none was needed"
    else
        pass "healthy backups are left alone"
    fi

    # Stale backups: the wrapper must run one backup, then re-check health.
    sandbox="$TMP_ROOT/stale"
    make_sandbox "$sandbox"
    out="$TMP_ROOT/stale.out"
    TEST_HEALTH_MODE=becomes-healthy \
    TEST_HEALTH_LOG="$TMP_ROOT/stale.health" \
    TEST_BACKUP_LOG="$TMP_ROOT/stale.backup" \
    TEST_BACKUP_MARKER="$TMP_ROOT/stale.marker" \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/run" XDG_STATE_HOME="$sandbox/state" \
    PATH="$sandbox/bin:$PATH" \
        "$sandbox/scripts/backups/run-missed-backups.sh" >"$out" 2>&1
    stale_status=$?
    health_calls=$(wc -l < "$TMP_ROOT/stale.health" 2>/dev/null || echo 0)
    if [ "$stale_status" -ne 0 ]; then
        fail "stale path exited $stale_status"
    elif [ ! -f "$TMP_ROOT/stale.backup" ]; then
        fail "stale path did not run a backup"
    elif [ "$health_calls" -lt 2 ]; then
        fail "stale path did not re-check health after backing up"
    else
        pass "stale backups trigger one backup and a verification check"
    fi

    # Backup runs but health stays bad: the unit must fail so systemd records it.
    sandbox="$TMP_ROOT/failing"
    make_sandbox "$sandbox"
    out="$TMP_ROOT/failing.out"
    TEST_HEALTH_MODE=fail \
    TEST_HEALTH_LOG="$TMP_ROOT/failing.health" \
    TEST_BACKUP_LOG="$TMP_ROOT/failing.backup" \
    TEST_BACKUP_MARKER="$TMP_ROOT/failing.marker" \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/run" XDG_STATE_HOME="$sandbox/state" \
    PATH="$sandbox/bin:$PATH" \
        "$sandbox/scripts/backups/run-missed-backups.sh" >"$out" 2>&1
    failing_status=$?
    if [ "$failing_status" -eq 0 ]; then
        fail "a backup that leaves health failing still exits success"
    elif [ ! -f "$TMP_ROOT/failing.backup" ]; then
        fail "failing path did not attempt a backup"
    else
        pass "a failed catch-up exits non-zero"
    fi

    # Lock held by another catch-up: skip instead of starting a parallel run.
    sandbox="$TMP_ROOT/locked"
    make_sandbox "$sandbox"
    lock="$sandbox/run/spectre-suite-backup-catchup.lock"
    (
        exec 9>"$lock"
        flock -n 9 || exit 1
        touch "$TMP_ROOT/lock-held"
        sleep 2
    ) &
    lock_pid=$!
    for _ in $(seq 1 100); do
        [ -f "$TMP_ROOT/lock-held" ] && break
        sleep 0.02
    done
    out="$TMP_ROOT/locked.out"
    TEST_HEALTH_MODE=healthy \
    TEST_HEALTH_LOG="$TMP_ROOT/locked.health" \
    TEST_BACKUP_LOG="$TMP_ROOT/locked.backup" \
    TEST_BACKUP_MARKER="$TMP_ROOT/locked.marker" \
    HOME="$sandbox/home" XDG_RUNTIME_DIR="$sandbox/run" XDG_STATE_HOME="$sandbox/state" \
    PATH="$sandbox/bin:$PATH" \
        "$sandbox/scripts/backups/run-missed-backups.sh" >"$out" 2>&1
    locked_status=$?
    wait "$lock_pid" 2>/dev/null || true
    if [ "$locked_status" -ne 0 ]; then
        fail "busy lock exited $locked_status instead of skipping cleanly"
    elif [ -f "$TMP_ROOT/locked.backup" ]; then
        fail "busy lock still started a backup"
    elif ! grep -qiE 'already|locks?' "$out"; then
        fail "busy lock did not explain why it skipped"
    else
        pass "a held lock prevents overlapping catch-up runs"
    fi
fi

echo ""
echo "Backup catch-up tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
