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
#
# This has to check systemd user units as well as crontab. The first version only
# read crontab, so it passed while six systemd timers were still running the fork:
# backup.service was writing 58-byte hollow archives over the real database and
# copying other projects' volumes every night at 02:00, and docker-cleanup.service
# was running an unscoped host-wide `docker volume prune -f`. Both logged success.
# A guard that only inspects one of the two schedulers is worse than none, because
# it reads as coverage.
scheduled=$(printf '%s\n' "$cron")

if systemctl --user list-unit-files --no-legend >/dev/null 2>&1; then
    for unit in "$HOME"/.config/systemd/user/*.service; do
        [ -f "$unit" ] || continue
        # Only units a timer can actually trigger.
        base=$(basename "$unit" .service)
        # Not anchored: list-timers lines start with the next-run timestamp, so
        # "^${base}\.timer" matched nothing and the guard passed vacuously.
        if ! systemctl --user list-timers --all --no-legend 2>/dev/null \
             | grep -qE "(^|[[:space:]])${base}\.timer([[:space:]]|$)"; then
            continue
        fi
        exec_line=$(grep -oE '^ExecStart=.*' "$unit" | head -1)
        [ -n "$exec_line" ] && scheduled="$scheduled"$'\n'"$exec_line"
    done
else
    echo "note: systemd user units unavailable, checking crontab only"
fi

# System units are a third scheduler, and the one that hid the longest.
#
# disk-space-check and security-scan live in /etc/systemd/system and run on
# timers as root. The first two versions of this guard read crontab, then
# crontab plus user units -- and passed while those two system units were
# failing every single run with status=217/USER, because `User=$USER_NAME` is
# not expanded by systemd without an EnvironmentFile. security-scan had never
# succeeded at all: one journal line, and it was the failure itself. A weekly
# security scan that reports success because the check never looks at it is the
# worst outcome this suite has produced.
#
# /etc/systemd/system is root-owned and unreadable to a non-root CI runner, so
# these assertions skip rather than fail off-host. On the real host they are the
# only thing covering these units.
for unit_dir in /etc/systemd/system; do
    [ -d "$unit_dir" ] || continue
    for unit in "$unit_dir"/*.service; do
        [ -r "$unit" ] || continue
        base=$(basename "$unit" .service)
        if ! systemctl list-timers --all --no-legend 2>/dev/null \
             | grep -qE "(^|[[:space:]])${base}\.timer([[:space:]]|$)"; then
            continue
        fi
        exec_line=$(grep -oE '^ExecStart=.*' "$unit" | head -1)
        [ -n "$exec_line" ] && scheduled="$scheduled"$'\n'"$exec_line"
    done
done

# Strip the "ExecStart=" prefix systemd lines carry, or the token never matches
# the fork-root prefix test and a fork script slips through under any name the
# repository does not also provide.
outside=$(printf '%s\n' "$scheduled" \
    | grep -oE '(^|[[:space:]])[^[:space:]]+\.sh' \
    | tr -d ' ' \
    | sed 's/^ExecStart=//' \
    | grep -v "^$PROJECT_ROOT/" \
    | sort -u || true)

# Two distinct things can appear here, and only one is our problem.
#
#   1. A copy of a script this repository provides, living somewhere else. That
#      is the drift that let a fork keep running: backup-all.sh wrote hollow
#      archives over the real database nightly and docker-cleanup.sh ran unscoped
#      host-wide volume prunes, both from /home/deon/scripts.
#   2. Another project's tool entirely -- this host also runs arcaden-labs'
#      docker-gc and a KDE helper. Those are not ours to relocate, and failing the
#      build over them would train everyone to ignore the check.
#
# So: fail on the fork root, and on any basename this repo also provides.
# Everything else is reported and allowed.
FORK_ROOTS="/home/deon/scripts/"
repo_scripts=$(cd "$PROJECT_ROOT" && find scripts prometheus -name '*.sh' -printf '%f\n' 2>/dev/null | sort -u)

offenders=""
foreign=""
for path in $outside; do
    if [ -z "$path" ]; then continue; fi
    case "$path" in
        "$FORK_ROOTS"*)
            offenders="$offenders$path"$'\n'
            continue
            ;;
    esac
    base=$(basename "$path")
    if printf '%s\n' "$repo_scripts" | grep -qx "$base"; then
        offenders="$offenders$path"$'\n'
    else
        foreign="$foreign$path"$'\n'
    fi
done

if [ -z "$offenders" ]; then
    pass "no scheduled script is a stale copy of one this repository provides"
else
    fail "scheduled scripts are copies of repository scripts, living elsewhere:"
    printf '%s' "$offenders" | sed 's/^/     /'
    echo "     Point the unit or crontab entry at $PROJECT_ROOT"
fi

# 1b. A systemd unit that cannot start is a silent failure, and it is invisible
# to every other check here. This is the assertion that would have caught
# security-scan never running at all.
#
# `User=$USER_NAME` reads as a literal username to systemd; it is not a shell
# variable, so nothing expands it and the unit dies 217/USER before ExecStart is
# ever reached. Both system units here had that, and both had been failing while
# the suite reported healthy.
unstartable=""
for unit in /etc/systemd/system/*.service; do
    [ -r "$unit" ] || continue
    base=$(basename "$unit" .service)
    if ! systemctl list-timers --all --no-legend 2>/dev/null \
         | grep -qE "(^|[[:space:]])${base}\.timer([[:space:]]|$)"; then
        continue
    fi
    if grep -qE '^(User|Group)=\$[A-Za-z_]' "$unit" 2>/dev/null; then
        unstartable="$unstartable$(basename "$unit") ($(grep -oE '^(User|Group)=\$[A-Za-z_]+' "$unit" | head -1))"$'\n'
    fi
done
if [ -z "$unstartable" ]; then
    pass "no timer-triggered system unit uses an unexpanded \$VAR for User/Group"
else
    fail "timer-triggered system units cannot start -- systemd does not expand shell variables:"
    printf '%s' "$unstartable" | sed 's/^/     /'
    echo "     Use a literal username, or supply the value via EnvironmentFile="
fi

# 1c. Every scheduled unit must point at a script that exists. A path under a
# system location can be truncated or mangled by a bad edit and still look
# plausible in review; asserting the target is a real file catches it. This is
# the check that would have caught a broken ExecStart=/performance/... left
# behind by a variable that failed to expand.
missing_targets=""
for path in $outside; do
    [ -n "$path" ] || continue
    case "$path" in
        /usr/bin/*|/usr/sbin/*|/bin/*|/sbin/*|/usr/local/sbin/*) continue ;;
    esac
    # systemd's %h specifier is expanded at runtime, not by us. A path written
    # this way is a real, working target -- treating it as missing would fail on
    # a unit that runs fine, which is how a guard gets ignored.
    case "$path" in
        %h/*|~/*|%i/*) continue ;;
    esac
    if [ ! -e "$path" ]; then
        missing_targets="$missing_targets$path"$'\n'
    fi
done
if [ -z "$missing_targets" ]; then
    pass "every scheduled script target exists on this host"
else
    fail "scheduled script targets do not exist:"
    printf '%s' "$missing_targets" | sed 's/^/     /'
    echo "     A scheduled path that does not exist fails on every run"
fi

if [ -n "$foreign" ]; then
    # Informational: these belong to other projects installed on this host.
    echo "  note: ignoring scheduled scripts belonging to other projects:"
    printf '%s' "$foreign" | sed 's/^/     /'
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
done < <(printf '%s\n' "$scheduled" | grep -oE '[^[:space:]]+\.sh' | sort -u || true)
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
