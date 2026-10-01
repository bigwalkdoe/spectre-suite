#!/bin/bash
# Scheduled-job ownership tests
#
# The repository was fixed while a stale fork of these same scripts kept running
# on schedule from /home/deon/scripts. Every job reported success: the backups
# wrote 81 empty archives, replication claimed to have run when it had not, and
# vacuuming had never executed at all. No repository-level check could see it,
# because the repository was not what was running.
#
# These assertions look at the host's crontab and catch exactly that. They skip
# cleanly where there is no crontab, so CI on a runner is unaffected.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Running scheduled-job ownership tests..."

if ! command -v crontab >/dev/null 2>&1 || ! crontab -l >/dev/null 2>&1; then
    echo "SKIP: no crontab on this host (normal in CI)"
    exit 0
fi

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

cron=$(crontab -l 2>/dev/null | grep -vE '^\s*#')

# 1. No scheduled script may live outside this repository.
outside=$(printf '%s\n' "$cron" \
    | grep -oE '(^|[[:space:]])[^[:space:]]+\.sh' \
    | tr -d ' ' \
    | grep -v "^$PROJECT_ROOT/" \
    | sort -u || true)
if [ -z "$outside" ]; then
    pass "every scheduled script lives in this repository"
else
    fail "scheduled scripts exist outside the repository:"
    printf '%s\n' "$outside" | sed 's/^/     /'
fi

# 2. Every script this repository schedules must exist and be executable.
missing=0
while read -r script; do
    [ -n "$script" ] || continue
    case "$script" in
        "$PROJECT_ROOT"/*) ;;
        *) continue ;;
    esac
    if [ ! -f "$script" ]; then
        fail "cron references a script that does not exist: $script"
        missing=1
    elif [ ! -x "$script" ]; then
        # A cron job with no executable bit fails with "Permission denied" and
        # writes nothing. business-metrics-exporter.sh shipped that way and had
        # never produced a single file.
        fail "cron references a script that is not executable: $script"
        missing=1
    fi
done < <(printf '%s\n' "$cron" | grep -oE '[^[:space:]]+\.sh' | sort -u || true)
[ "$missing" -eq 0 ] && pass "every scheduled repository script exists and is executable"

# 3. The destructive maintenance scripts must accept --dry-run. Their whole
#    value as scheduled jobs is that they are unattended, so being able to see
#    what they would remove first is the only review available.
for script in cleanup-unused-resources cleanup-temp cleanup-cache cleanup-downloads; do
    path="$PROJECT_ROOT/scripts/maintenance/$script.sh"
    if [ ! -f "$path" ]; then
        fail "expected maintenance script is missing: $script.sh"
        continue
    fi
    if grep -q -- '--dry-run' "$path"; then
        pass "$script.sh supports --dry-run"
    else
        fail "$script.sh has no --dry-run and runs unattended"
    fi
done

echo ""
echo "Schedule ownership tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
