#!/bin/bash
# Label the repository so a *system* systemd unit can execute its scripts.
#
# Why this exists
# ---------------
# This repository lives in the user's home directory. Both user-level and
# system-level timers execute scripts from it. Those two cases are not
# equivalent under SELinux, and the difference is invisible until a unit fails:
#
#   * ~/.config/systemd/user/*.service runs as deon in the unconfined_u domain,
#     which is permitted to execute user_home_t. These have always worked.
#
#   * /etc/systemd/system/*.service is exec'd by PID 1 in system_u/init_t before
#     the uid switch to deon. That domain is not permitted to execute
#     user_home_t, so the unit fails at 203/EXEC with "Unable to locate
#     executable ... Permission denied" -- even though the file is rwxr-xr-x,
#     owned by deon, and every parent directory is traversable.
#
# disk-space-check and security-scan both failed this way on every scheduled run.
# disk-space-check had been failing since at least the previous day and
# security-scan had never succeeded once, so a weekly security scan was
# reporting nothing at all.
#
# Why `restorecon -R` is not enough
# ---------------------------------
# No SELinux fcontext rule covers a checkout under $HOME, so there is no policy
# default for restorecon to apply and it silently changes nothing. The label has
# to be set explicitly, and it has to be `shell_exec_t`: a type the system
# domain is allowed to execute. `user_home_t` is correct for data and wrong for
# code.
#
# The user's own `.local/bin` and home files are untouched -- this only touches
# the repository, and only shell scripts within it.
#
# Usage:  sudo ./scripts/systemd/label-exec-context.sh [--check]
#         --check reports the current labels and exits non-zero if any shell
#         script is not executable by the system domain. Safe to run unprivileged.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXEC_TYPE="shell_exec_t"
CHECK_ONLY=0
[ "${1:-}" = "--check" ] && CHECK_ONLY=1

if ! command -v semanage >/dev/null 2>&1; then
    echo "ERROR: semanage not found. Install policycoreutils-python-utils." >&2
    exit 1
fi

# Only shell scripts. Labelling data files executable would be wrong in the
# other direction, and the .git directory is skipped for the same reason.
mapfile -t targets < <(
    find "$REPO_ROOT" -path "$REPO_ROOT/.git" -prune -o \
        -type f -name '*.sh' -print 2>/dev/null | sort
)

if [ "${#targets[@]}" -eq 0 ]; then
    echo "No shell scripts found under $REPO_ROOT" >&2
    exit 1
fi

# Every shell script needs the exec type; the directories only need to be
# traversable, which user_home_t already permits. Labelling directories was the
# mistake that produced a half-applied state, so they are left alone.
if [ "$CHECK_ONLY" -eq 0 ]; then
    echo "Applying SELinux fcontext rule: $REPO_ROOT/**/*.sh -> $EXEC_TYPE"
    semanage fcontext -a -t "$EXEC_TYPE" "$REPO_ROOT(/.*)?\.sh" 2>/dev/null \
        || semanage fcontext -m -t "$EXEC_TYPE" "$REPO_ROOT(/.*)?\.sh"
    restorecon -RFv "$REPO_ROOT" >/dev/null
    echo "Applied."
else
    echo "Checking exec labels under $REPO_ROOT ..."
fi

# Report the SELinux user component too. `chcon -t` rewrites only the type and
# leaves the user as whatever it was, which is how directories ended up
# system_u while their files were unconfined_u -- a mixed state that looks fixed
# if you only read the type column.
bad=0
declare -A user_seen=()
for t in "${targets[@]}"; do
    label=$(ls -Zd "$t" 2>/dev/null | awk '{print $1}')
    [ -n "$label" ] || continue
    type=$(printf '%s' "$label" | cut -d: -f3)
    selinux_user=$(printf '%s' "$label" | cut -d: -f1)
    user_seen["$selinux_user"]=1
    if [ "$type" != "$EXEC_TYPE" ]; then
        echo "  NOT EXECUTABLE BY SYSTEM DOMAIN: $t"
        echo "      label: $label (expected type $EXEC_TYPE)"
        bad=1
    fi
done

echo
echo "SELinux users seen across shell scripts: ${!user_seen[*]}"

if [ "$bad" -ne 0 ]; then
    echo
    echo "RESULT: at least one script is not executable by a system systemd unit."
    echo "Fix:    sudo $0"
    exit 1
fi

echo "RESULT: all ${#targets[@]} shell script(s) labelled $EXEC_TYPE."
echo "System units will now exec them. Verify with:"
echo "  systemctl start disk-space-check.service security-scan.service"