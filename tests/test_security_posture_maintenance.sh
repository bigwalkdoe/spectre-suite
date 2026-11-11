#!/bin/bash
# Security posture maintenance action tests (Task 5)
#
# Verifies lightweight 15-min posture maintenance: status markers, safe/idempotent
# remediation bounded to managed state, and dry-run/check-only no-side-effects.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
MAINT="$PROJECT_ROOT/spectre/actions/security/security-posture-maintenance.sh"

echo "Running security posture maintenance tests..."

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

if [ ! -f "$MAINT" ]; then
    echo "❌ security-posture-maintenance.sh does not exist (expected failure for RED)"
    exit 1
fi
if [ ! -x "$MAINT" ]; then
    chmod +x "$MAINT"
fi

new_env() {
    WORK=$(mktemp -d "${TMPDIR:-/tmp}/security-posture-test.XXXXXX")
    HOME_DIR="$WORK/home"
    XDG_STATE_HOME="$WORK/state"
    BIN_DIR="$WORK/bin"
    mkdir -p "$HOME_DIR" "$XDG_STATE_HOME" "$BIN_DIR"
    STATE_DIR="$XDG_STATE_HOME/spectre-suite/security-posture"
    SPECTRE_LOG="$WORK/spectre.calls"

    # Stub spectre: record invocations; succeed for known lightweight posture refresh.
    cat > "$BIN_DIR/spectre" <<'EOF'
#!/bin/bash
echo "$*" >> "${SPECTRE_LOG:?}"
case "$*" in
  "run prometheus/security-baseline-metrics-exporter"|"run prometheus/security-metrics-exporter")
    exit 0
    ;;
  *)
    # unknown/unavailable components should be handled gracefully by maintenance
    exit 0
    ;;
esac
EOF
    chmod +x "$BIN_DIR/spectre"
    export PATH="$BIN_DIR:$PATH"
    export HOME="$HOME_DIR"
    export XDG_STATE_HOME="$XDG_STATE_HOME"
    export SPECTRE_LOG
}

cleanup_env() {
    rm -rf "$WORK"
}

run_maint() {
    "$MAINT" "$@" 2>&1
}

# 1) Creates/updates status marker/summary in state dir and exits 0 on success
test_success_marker() {
    local out rc
    new_env
    out=$(run_maint); rc=$?
    if [ "$rc" -eq 0 ] && [ -d "$STATE_DIR" ]; then
        # status summary/marker present with timestamp/result indicators
        if find "$STATE_DIR" -maxdepth 2 -type f | grep -q . \
           && grep -RqiE "timestamp|time|result|overall|status|checks|remediation" "$STATE_DIR" 2>/dev/null; then
            pass "creates status marker/summary in state dir and exits 0"
        else
            fail "missing status summary/marker content in state dir"
            printf '%s\n' "$out" | sed 's/^/     /'
            find "$STATE_DIR" -maxdepth 3 -print 2>/dev/null | sed 's/^/     /'
        fi
    else
        fail "expected exit 0 and state dir created (rc=$rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
    cleanup_env
}

# 2) --dry-run/--check-only does not apply filesystem cleanup/remediation side effects
test_dry_run_no_side_effects() {
    local out rc outside managed_tmp stale recent
    new_env
    managed_tmp="$STATE_DIR/tmp"
    mkdir -p "$managed_tmp"
    stale="$managed_tmp/stale.tmp"
    recent="$managed_tmp/recent.tmp"
    printf 'stale' > "$stale"
    printf 'recent' > "$recent"
    touch -d "2 days ago" "$stale" 2>/dev/null || touch -t 202001010000 "$stale"
    touch "$recent"
    outside="$WORK/outside-arbitrary.txt"
    printf 'keep' > "$outside"
    touch -d "2 days ago" "$outside" 2>/dev/null || touch -t 202001010000 "$outside"

    out=$(run_maint --dry-run); rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "--dry-run exited non-zero (rc=$rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
        cleanup_env; return
    fi
    if [ -f "$stale" ] && [ -f "$recent" ] && [ -f "$outside" ]; then
        # also should not have "applied" remediation beyond reporting; marker may be written as report-only is fine
        pass "--dry-run/check-only does not apply filesystem cleanup/remediation side effects"
    else
        fail "--dry-run applied filesystem side effects"
        printf '%s\n' "$out" | sed 's/^/     /'
        ls -la "$managed_tmp" "$WORK" 2>/dev/null | sed 's/^/     /'
    fi
    # --check-only alias if supported
    out=$(run_maint --check-only); rc=$?
    if [ "$rc" -eq 0 ] && [ -f "$stale" ] && [ -f "$outside" ]; then
        pass "--check-only behaves as no-remediation mode"
    else
        fail "--check-only applied side effects or failed (rc=$rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
    fi
    cleanup_env
}

# 3) Safe remediation creates expected state dirs and removes only stale temp files
#    in managed posture temp area (not arbitrary files) when applicable.
test_safe_remediation() {
    local out rc managed_tmp stale recent outside outside_stale
    new_env
    managed_tmp="$STATE_DIR/tmp"
    mkdir -p "$managed_tmp"
    stale="$managed_tmp/stale.tmp"
    recent="$managed_tmp/recent.tmp"
    printf 'stale' > "$stale"
    printf 'recent' > "$recent"
    touch -d "2 days ago" "$stale" 2>/dev/null || touch -t 202001010000 "$stale"
    touch "$recent"
    outside="$WORK/outside-arbitrary.txt"
    outside_stale="$WORK/outside-stale.txt"
    printf 'keep' > "$outside"
    printf 'keep2' > "$outside_stale"
    touch -d "2 days ago" "$outside_stale" 2>/dev/null || touch -t 202001010000 "$outside_stale"

    # remove state dir except managed tmp content to verify dirs created
    # (state dir already exists partially; ensure full expected dirs created)
    out=$(run_maint); rc=$?
    if [ "$rc" -ne 0 ]; then
        fail "safe remediation run failed (rc=$rc)"
        printf '%s\n' "$out" | sed 's/^/     /'
        cleanup_env; return
    fi
    if [ -d "$STATE_DIR" ] && [ ! -f "$stale" ] && [ -f "$recent" ] \
       && [ -f "$outside" ] && [ -f "$outside_stale" ]; then
        pass "creates expected state dirs and removes only stale managed temp files"
    else
        fail "safe remediation scope/behavior incorrect"
        printf '%s\n' "$out" | sed 's/^/     /'
        echo "     stale exists? $([ -f "$stale" ] && echo yes || echo no)" >&2
        echo "     recent exists? $([ -f "$recent" ] && echo yes || echo no)" >&2
        echo "     outside exists? $([ -f "$outside" ] && echo yes || echo no)" >&2
        echo "     outside_stale exists? $([ -f "$outside_stale" ] && echo yes || echo no)" >&2
        find "$WORK" -maxdepth 4 -print 2>/dev/null | sed 's/^/     /'
    fi
    cleanup_env
}

test_success_marker
test_dry_run_no_side_effects
test_safe_remediation

echo ""
echo "Security posture maintenance tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
