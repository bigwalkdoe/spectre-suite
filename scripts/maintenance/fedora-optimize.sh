#!/usr/bin/env bash
#
# Fedora Safe Optimizer
#
# Production-grade, idempotent, rollback-capable optimizer for Fedora 44.
#
# Design:
#   - dry-run is strictly READ-ONLY
#   - every file/system change is timestamped-backed-up and manifest-tracked
#   - rollback restores the exact prior state (files, services, sysctls)
#   - newest 10 backup sets retained
#   - SELinux contexts restored via restorecon after every system write
#   - cache-only ops are regenerable and intentionally NOT restored
#
# Usage:
#   fedora-optimize --dry-run                  (default; read-only plan)
#   fedora-optimize --apply                    apply safe optimizations
#   fedora-optimize --apply --deep             also docker/repo-deps (confirmed)
#   fedora-optimize --list-backups
#   fedora-optimize --rollback <timestamp>
#   fedora-optimize --scope user|system|all    restrict operations
#
# System ops require root. User ops (baloo, user caches) run as the
# invoking user via runuser when elevated.

set -Eeuo pipefail

##############################################################################
# Constants
##############################################################################

BACKUP_ROOT="/var/backups/fedora-optimizer"
LOCK_FILE="${TMPDIR:-/tmp}/fedora-optimize-${UID:-$(id -u)}.lock"
# One shared log regardless of the invoking user (HOME differs under sudo).
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/logs/fedora-optimize.log"
JOURNAL_LIMIT=200000000                # bytes (== SystemMaxUse of 200M)
PACKAGEKIT_THRESHOLD=$((100 * 1024 * 1024))
ROTATED_KEEP=2
CACHE_AGE_DAYS=90
MANIFEST_KIND_FILE="file"
MANIFEST_KIND_SERVICE="service"

MODE="${MODE:-}"
SCOPE="${SCOPE:-all}"
DEEP=0
ASSUME_YES=0

# Effective user (the person who invoked us, honouring sudo)
REAL_USER="${SUDO_USER:-$(id -un)}"
if [[ "$REAL_USER" == "root" ]]; then
    REAL_USER="$(logname 2>/dev/null || echo root)"
fi
USER_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[[ -n "$USER_HOME" ]] || USER_HOME="/home/${REAL_USER}"

EUID_ACT="$(id -u)"
IS_ROOT=0
[[ "$EUID_ACT" -eq 0 ]] && IS_ROOT=1

# Backup set identity
TIMESTAMP="$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
TREE_DIR="${BACKUP_DIR}/tree"
MANIFEST="${BACKUP_DIR}/manifest"

FREED_TOTAL=0
SKIP_REASON=""

##############################################################################
# Helpers
##############################################################################

usage() {
    cat <<EOF
Fedora Safe Optimizer

Usage:
  sudo $0 --dry-run
  sudo $0 --apply [--deep] [--scope user|system|all] [-y]
  sudo $0 --list-backups
  sudo $0 --rollback <timestamp>

Options:
  --dry-run           Plan only. Makes no changes to the system.
  --apply             Apply the safe optimizations.
  --deep              Also clean docker build cache/dangling images and
                      node_modules in idle repos (interactive confirm).
  --scope user|system Restrict to user-owned or system operations.
  -y                  Assume yes (skip interactive confirmations).
  --list-backups      Show available rollback points.
  --rollback <ts>     Restore the exact prior state of that set.

Backups: $BACKUP_ROOT (newest 10 sets retained)
EOF
}

say()  { printf '[INFO]  %s\n' "$*"; }
warn() { printf '[WARN]  %s\n' "$*" >&2; }
fail() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

log_to_file() { mkdir -p "$(dirname "$LOG_FILE")"; printf '[%s] %s\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE"; }

# Unified action executor: in dry-run it only prints the plan.
action() {
    if [[ "$MODE" == "--apply" ]]; then
        "$@"
    else
        printf '[DRY-RUN] would run: %s\n' "$*"
    fi
}

# Report a "would change" or "doing" line for an op.
plan() {
    if [[ "$MODE" == "--apply" ]]; then
        say "$*"
    else
        printf '[DRY-RUN] %s\n' "$*"
    fi
}

skip() { warn "SKIP: $*"; }

is_scope() { # scope_op system|user
    local need="$1"
    if [[ "$SCOPE" == "all" ]]; then return 0; fi
    [[ "$SCOPE" == "$need" ]]
}

require_system() { # system ops need root
    [[ "$MODE" == "--apply" && "$IS_ROOT" -eq 1 ]] || [[ "$MODE" == "--dry-run" ]]
}

# Run a command as the real (unprivileged) user, even when elevated.
run_as_user() {
    if [[ "$IS_ROOT" -eq 1 && "$REAL_USER" != "root" ]]; then
        # Provide an environment for the user's D-Bus session if findable.
        # Guard every --env (unset vars would trip `set -u` and kill the shell).
        local bpid bus xdg envargs=()
        bpid="$(pgrep -u "$REAL_USER" -f baloo_file 2>/dev/null | head -n1)"
        if [[ -n "${bpid:-}" ]]; then
            bus="$(tr '\0' '\n' < "/proc/${bpid}/environ" 2>/dev/null | grep '^DBUS_SESSION_BUS_ADDRESS=' || true)"
            xdg="$(tr '\0' '\n' < "/proc/${bpid}/environ" 2>/dev/null | grep '^XDG_RUNTIME_DIR=' || true)"
        fi
        [[ -n "${bus:-}" ]] && envargs+=(--env="$bus")
        [[ -n "${xdg:-}" ]] && envargs+=(--env="$xdg")
        runuser -u "$REAL_USER" "${envargs[@]}" -- "$@"
    else
        "$@"
    fi
}

human() { numfmt --to=iec-i --suffix=B "$1" 2>/dev/null || echo "$1"; }

fsize() { du -sb "$1" 2>/dev/null | awk '{print $1}' || echo 0; }

record_freed() { FREED_TOTAL=$((FREED_TOTAL + $1)); }

# SELinux-safe write: place a generated file and restore its context.
install_generated() { # <content_file|-> <target>
    local src="$1" target="$2"
    install -D -m 0644 -o root -g root "$src" "$target"
    restorecon -F "$target"
}

##############################################################################
# Backup / manifest / retention
##############################################################################

# Back up one existing file into the mirrored tree under the backup set.
# Returns 0 if a copy was made, 1 if the path did not exist (i.e. we will
# "create" it and rollback removes it).
backup_to_tree() {
    local abs="$1"
    if [[ ! -e "$abs" ]]; then
        return 1
    fi
    local rel="${abs#/}"
    mkdir -p "${TREE_DIR}"
    ( cd / && cp -a --parents --preserve=context,ownership,mode "$rel" "${TREE_DIR}/" )
    return 0
}

# sha256 of the mirrored tree copy for a path ('' if no copy exists) so the
# manifest records the exact byte identity that rollback can restore.
tree_sha() { # <path>
    local rel="${1#/}"
    [[ -f "${TREE_DIR}/${rel}" ]] || { echo '-'; return; }
    sha256sum "${TREE_DIR}/${rel}" | awk '{print $1}'
}

record_manifest() { # <kind> <op_id> <path> <sha256> <created:0|1>
    if [[ "$MODE" == "--apply" ]]; then
        # Emit '-' for empty optional fields: adjacent tabs would collapse
        # during IFS=$'\t' read and misplace the trailing created flag.
        local sha="${4:--}" flag="${5:--}"
        printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$sha" "$flag" >> "$MANIFEST"
    fi
}

write_backup_setup_metadata() {
    if [[ "$MODE" != "--apply" ]]; then return; fi
    mkdir -p "$BACKUP_DIR"
    cat > "${BACKUP_DIR}/metadata.txt" <<EOF
Timestamp: ${TIMESTAMP}
Hostname: $(hostname)
Kernel: $(uname -r)
Created-by: fedora-safe-optimizer
User: ${REAL_USER}
Scope: ${SCOPE}
EOF
}

# Date-stamped dirs sort lexicographically; newest first, drop beyond the
# 10 most recent sets. Sets left without manifest entries (interrupted run,
# or a run that applied nothing) are junk and are pruned as well.
cleanup_old_backups() {
    [[ -d "$BACKUP_ROOT" ]] || return 0
    find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d \
        | sort -r \
        | tail -n +11 \
        | xargs -r rm -rf
    if [[ "$IS_ROOT" -eq 1 ]]; then
        local d
        for d in "$BACKUP_ROOT"/*/; do
            [ -d "$d" ] || continue
            if [[ ! -f "${d}manifest" ]] || [[ ! -s "${d}manifest" ]]; then
                log_to_file "removed empty backup set ${d%/}"
                rm -rf "$d"
            fi
        done
    fi
    say "Backup retention enforced: newest 10 sets kept."
}

list_backups() {
    echo
    echo "Available backup sets (newest first)"
    echo "===================================="
    if [[ ! -d "$BACKUP_ROOT" ]] || [[ -z "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]]; then
        echo "No backups found."
        return
    fi
    for set_dir in $(find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d | sort -r); do
        local meta files
        meta="$(awk -F': ' '/Timestamp/{t=$2}/User/{u=$2}END{printf "[%s] by %s",t,u}' "${set_dir}/metadata.txt" 2>/dev/null || echo "?")"
        files=0
        [[ -f "${set_dir}/manifest" ]] && files="$(wc -l < "${set_dir}/manifest")"
        printf '%-22s %-34s files:%s\n' "$(basename "$set_dir")" "$meta" "$files"
    done
}

##############################################################################
# Rollback
##############################################################################

rollback() {
    local backup_set="${1:-}"
    [[ -n "$backup_set" ]] || fail "Specify a backup timestamp: e.g. $(ls "$BACKUP_ROOT" 2>/dev/null | head -1)"
    local restore_dir="${BACKUP_ROOT}/${backup_set}"
    [[ -d "$restore_dir" ]] || fail "Backup set not found: ${backup_set}"
    [[ -f "${restore_dir}/manifest" ]] || fail "Backup set has no manifest; cannot roll back: ${backup_set}"

    local tree="${restore_dir}/tree"
    local restarted_journald=0 ran_sysctl=0

    echo
    echo "Rolling back backup set: ${backup_set}"
    echo "========================================"

    while IFS=$'\t' read -r kind op path sha created; do
        [[ -n "$kind" ]] || continue
        case "$kind" in
            "$MANIFEST_KIND_FILE")
                if [[ "$created" == "1" ]]; then
                    rm -f "$path"
                    echo "REMOVED  (was created by optimizer): $path"
                else
                    [[ -f "${tree}${path}" ]] || { warn "missing tree copy for $path; skipping"; continue; }
                    cp -a "${tree}${path}" "$path"
                    echo "RESTORED $path"
                    if [[ "$path" == /etc/* ]]; then
                        restorecon -F "$path"
                    fi
                fi
                ;;
            "$MANIFEST_KIND_SERVICE")
                # "op" is the unit name; we enabled it => inverse is disable.
                if systemctl is-enabled --quiet "$op" 2>/dev/null; then
                    systemctl disable "$op" >/dev/null 2>&1 || warn "could not disable $op"
                    echo "DISABLED service: $op"
                else
                    echo "SKIP      service $op (already disabled)"
                fi
                ;;
            *)
                warn "Unknown manifest kind: $kind";;
        esac

        # Reload daemons once, iff config that affects them was restored.
        if [[ "$path" == /etc/systemd/journald.conf.d/* ]] && [[ "$restarted_journald" -eq 0 ]]; then
            systemctl restart systemd-journald || true
            restarted_journald=1
        fi
        if [[ "$path" == /etc/sysctl.d/* ]] && [[ "$ran_sysctl" -eq 0 ]]; then
            sysctl --system >/dev/null 2>&1 || true
            ran_sysctl=1
        fi
    done < "${restore_dir}/manifest"

    echo
    echo "NOTE: regenerable caches (journal, PackageKit, dnf, coredumps,"
    echo "      ~/.cache) are intentionally not restored."
    echo "Rollback complete."
}

##############################################################################
# Operations: each has check() + apply() split, so --dry-run never mutates.
##############################################################################
# Scope marker: system ops call require_system; user ops call is_scope user.
##############################################################################

# ---------------------------------------------------------------- journald
check_journal_dropin() {
    local f="/etc/systemd/journald.conf.d/zz-fedora-optimize.conf"
    if [[ -f "$f" ]] && grep -q '^SystemMaxUse=200M' "$f"; then
        return 1
    fi
    return 0
}

apply_journal_dropin() {
    require_system || return 0
    plan "Adding journald drop-in: SystemMaxUse=200M"
    local f="/etc/systemd/journald.conf.d/zz-fedora-optimize.conf"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    local created=1
    backup_to_tree "$f" && created=0
    mkdir -p "/etc/systemd/journald.conf.d"
    cat > /tmp/zz-fedora-optimize.conf <<EOF
[Journal]
SystemMaxUse=200M
RuntimeMaxUse=100M
EOF
    install_generated "/tmp/zz-fedora-optimize.conf" "$f"
    rm -f /tmp/zz-fedora-optimize.conf
    record_manifest "$MANIFEST_KIND_FILE" journald_dropin "$f" "$(tree_sha "$f")" "$created"
    systemctl restart systemd-journald || warn "journald restart failed"
    # Apply the limit immediately.
    run_cmd_journal_vacuum
}

run_cmd_journal_vacuum() {
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    journalctl --vacuum-size=200M >/dev/null 2>&1 || warn "journal vacuum failed"
}

# ----------------------------------------------------------------- vacuum
check_vacuum_journal() {
    local used
    used="$(journalctl --disk-usage 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?[KMGT]' | head -n1)"
    [[ -z "$used" ]] && return 1
    # Convert (e.g. "211.0M", "1.2G") to bytes, integer.
    local num unit bytes
    num="$(echo "$used" | grep -oE '[0-9.]+' | head -n1)"
    unit="$(echo "$used" | grep -oE '[KMGT]' | head -n1)"
    case "$unit" in
        G) bytes=$(( (${num%.*}) * 1024 * 1024 * 1024 )) ;;
        M) bytes=$(( (${num%.*}) * 1024 * 1024 )) ;;
        K) bytes=$(( (${num%.*}) * 1024 )) ;;
        *) bytes="${num%.*}" ;;
    esac
    [[ "$bytes" -gt "$JOURNAL_LIMIT" ]]
}

apply_vacuum_journal() {
    require_system || return 0
    is_scope system || return 0
    plan "Vacuuming journal to 200M (currently $(journalctl --disk-usage 2>/dev/null | tail -1 | sed 's/.*takes up //'))"
    if [[ "$MODE" == "--apply" ]]; then
        local before
        before="$(fsize /var/log/journal)"
        journalctl --vacuum-size=200M >/dev/null 2>&1
        after="$(fsize /var/log/journal)"
        record_freed $((before > after ? before - after : 0))
    fi
}

# ------------------------------------------------------------ packagekit
check_packagekit() {
    local total=0 p
    for p in /var/cache/PackageKit/*/metadata; do
        [[ -d "$p" ]] && total=$((total + $(fsize "$p")))
    done
    [[ "$total" -gt "$PACKAGEKIT_THRESHOLD" ]]
}

apply_packagekit() {
    require_system || return 0
    is_scope system || return 0
    local before=0 after=0
    for d in /var/cache/PackageKit/*/metadata; do [[ -d "$d" ]] && before=$((before + $(fsize "$d"))); done
    plan "Purging PackageKit metadata cache (${PACKAGEKIT_THRESHOLD} > ${before}B)"
    if [[ "$MODE" == "--apply" ]]; then
        rm -rf /var/cache/PackageKit/*/metadata/* 2>/dev/null || true
        for d in /var/cache/PackageKit/*/metadata; do [[ -d "$d" ]] && after=$((after + $(fsize "$d"))); done
        record_freed $((before - after))
    fi
}

# -------------------------------------------------------- rotated logs
check_rotated_logs() {
    local n
    n="$(ls /var/log/messages-* 2>/dev/null | wc -l)"
    [[ "$n" -gt "$ROTATED_KEEP" ]]
}

apply_rotated_logs() {
    require_system || return 0
    is_scope system || return 0
    local olds
    olds="$(ls -t /var/log/messages-* 2>/dev/null | tail -n +$((ROTATED_KEEP + 1)))"
    [[ -z "$olds" ]] && { skip "no old rotated logs beyond keep=$ROTATED_KEEP"; return 0; }
    local before=0
    for f in $olds; do before=$((before + $(fsize "$f"))); done
    plan "Removing rotated logs beyond newest ${ROTATED_KEEP}: ${olds//$'\n'/ }"
    if [[ "$MODE" == "--apply" ]]; then
        for f in $olds; do rm -f "$f"; done
        record_freed "$before"
    fi
}

# ------------------------------------------------------- coredumps
check_coredumps() {
    compgen -G '/var/lib/systemd/coredump/*' >/dev/null 2>&1
}

apply_coredumps() {
    require_system || return 0
    is_scope system || return 0
    local before
    before="$(fsize /var/lib/systemd/coredump)"
    plan "Purging coredumps (${before}B) - systemd keeps only recent dumps automatically"
    if [[ "$MODE" == "--apply" ]]; then
        rm -rf /var/lib/systemd/coredump/* 2>/dev/null || true
        record_freed "$before"
    fi
}

# ------------------------------------------------------- dnf cleanup
check_dnf_clean() {
    [[ "$(fsize /var/cache/dnf)" -gt 0 ]]
}

apply_dnf_clean() {
    require_system || return 0
    is_scope system || return 0
    plan "Cleaning dnf package cache (dnf clean all)"
    if [[ "$MODE" == "--apply" ]]; then
        local before after
        before="$(fsize /var/cache/dnf)"
        dnf clean all >/dev/null 2>&1 || warn "dnf clean failed"
        after="$(fsize /var/cache/dnf)"
        record_freed $((before - after))
    fi
}

# ------------------------------------------- dnf5 speed drop-in
check_dnf5_speed() {
    require_system || return 0
    is_scope system || return 0
    local dropin=/etc/dnf/libdnf5.conf.d/00-fedora-optimize.conf
    [[ -f "$dropin" ]] || return 0
    grep -q '^max_parallel_downloads=10' "$dropin" || return 0
    return 1
}

apply_dnf5_speed() {
    require_system || return 0
    is_scope system || return 0
    local dropin=/etc/dnf/libdnf5.conf.d/00-fedora-optimize.conf
    plan "Speeding up dnf5: max_parallel_downloads=10 (libdnf5.conf.d drop-in)"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi

    # Native dnf5 config drop-in directory (verified via strace + reposdir
    # probe). /etc/dnf/dnf.conf.d is dnf4-only and is NOT read by dnf5.
    local created=1
    backup_to_tree "$dropin" && created=0
    mkdir -p /etc/dnf/libdnf5.conf.d
    cat > /tmp/fedora-optimize-dnf.conf <<EOF
[main]
max_parallel_downloads=10
EOF
    install_generated "/tmp/fedora-optimize-dnf.conf" "$dropin"
    rm -f /tmp/fedora-optimize-dnf.conf
    record_manifest "$MANIFEST_KIND_FILE" dnf5_speed "$dropin" "$(tree_sha "$dropin")" "$created"

    # dnf5 must still parse its config after our edit.
    dnf5 repolist >/dev/null 2>&1 || warn "dnf5 failed to parse config after dnf5_speed changes"
}

# ----------------------------------------------------------- inotify
apply_inotify() {
    require_system || return 0
    is_scope system || return 0
    local f="/etc/sysctl.d/zz-fedora-optimize-inotify.conf"
    plan "Raising inotify max_user_instances 256 -> 1024 (zz- drop-in wins sort order)"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    local created=1
    backup_to_tree "$f" && created=0
    cat > /tmp/99-inotify.conf <<EOF
fs.inotify.max_user_instances=1024
EOF
    install_generated "/tmp/99-inotify.conf" "$f"
    rm -f /tmp/99-inotify.conf
    record_manifest "$MANIFEST_KIND_FILE" inotify "$f" "$(tree_sha "$f")" "$created"
    sysctl --system >/dev/null 2>&1 || warn "sysctl reload failed"
}

check_inotify() {
    require_system || return 0
    local cur
    cur="$(sysctl -n fs.inotify.max_user_instances 2>/dev/null || echo 0)"
    # Action needed when the persistence file is missing (reboot would
    # regress to the distribution default) or the live value is below target.
    [[ -f /etc/sysctl.d/zz-fedora-optimize-inotify.conf ]] || return 0
    [[ "$cur" -lt 1024 ]]
}

# ------------------------------------------------------ baloo (user)
check_baloo() {
    is_scope user || return 1
    # Action needed only when content indexing is NOT already disabled.
    if [[ -f "${USER_HOME}/.config/baloofilerc" ]] \
        && grep -q '^only basic indexing=true' "${USER_HOME}/.config/baloofilerc"; then
        return 1
    fi
    return 0
}

apply_baloo() {
    is_scope user || return 0
    local cfg="${USER_HOME}/.config/baloofilerc"
    plan "Restricting baloo: metadata-only indexing + excluding build dirs ($cfg)"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    mkdir -p "${USER_HOME}/.config"
    local created=1
    if backup_to_tree "$cfg"; then created=0; fi
    cat > /tmp/baloofilerc <<EOF
[Basic Settings]
Indexing-Enabled=true
only basic indexing=true
exclude filters=*~,*.part,*.o,.svn,.git,.hg,node_modules,__pycache__,.venv,venv,target,build,dist,.next,.nuxt
exclude folders[\$e]=\$HOME/.cache,\$HOME/.config,\$HOME/.local/share/Steam,\$HOME/.local/share/containers,\$HOME/.local/share/opencode,\$HOME/.npm-global,\$HOME/.cargo,\$HOME/go,\$HOME/.claude,\$HOME/.codex,\$HOME/.cline,\$HOME/.cursor,\$HOME/.vscode,\$HOME/Downloads

[General]
dbVersion=2
EOF
    install -o "$REAL_USER" -g "$REAL_USER" -m 0644 /tmp/baloofilerc "$cfg"
    rm -f /tmp/baloofilerc
    restorecon -F "$cfg" 2>/dev/null || true
    record_manifest "$MANIFEST_KIND_FILE" baloo "$cfg" "$(tree_sha "$cfg")" "$created"
    run_as_user timeout 15 balooctl6 restart >/dev/null 2>&1 \
        || warn "baloo not active in this session; new settings apply on next start"
}

# --------------------------------------------------------- user caches
check_user_caches() {
    is_scope user || return 1
    local any=0 d
    for d in "${USER_HOME}/.cache/uv" "${USER_HOME}/.cache/pip" "${USER_HOME}/.cache/go-build" \
             "${USER_HOME}/.npm/_cacache" "${USER_HOME}/.local/share/pnpm" ; do
        [[ -d "$d" ]] && any=1
    done
    [[ -n "$(find "${USER_HOME}/.cache" -type f -mtime +${CACHE_AGE_DAYS} -print -quit 2>/dev/null)" ]] && any=1
    [[ "$any" -eq 1 ]]
}

apply_user_caches() {
    is_scope user || return 0
    plan "Clearing user caches: uv/pip/go-build/npm/pnpm + ~/.cache files older than ${CACHE_AGE_DAYS}d"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    local before after
    before="$(fsize "${USER_HOME}/.cache")"
    run_as_user uv cache clean >/dev/null 2>&1 || true
    run_as_user pip cache purge >/dev/null 2>&1 || true
    run_as_user rm -rf \
        "${USER_HOME}/.cache/pip" \
        "${USER_HOME}/.cache/go-build" \
        "${USER_HOME}/.npm/_cacache" \
        "${USER_HOME}/.local/share/pnpm" 2>/dev/null || true
    run_as_user find "${USER_HOME}/.cache" \( -type f -o -type l \) -mtime +${CACHE_AGE_DAYS} -delete 2>/dev/null || true
    after="$(fsize "${USER_HOME}/.cache")"
    record_freed $((before > after ? before - after : 0))
}

# --------------------------------------------------------------- fstrim
check_fstrim() {
    require_system || return 0
    is_scope system || return 0
    # Skip when already enabled.
    if systemctl is-enabled --quiet fstrim.timer 2>/dev/null; then
        return 1
    fi
    return 0
}

apply_fstrim() {
    require_system || return 0
    is_scope system || return 0
    plan "Enabling fstrim.timer (weekly TRIM)"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    systemctl enable --now fstrim.timer >/dev/null 2>&1 || warn "fstrim enable failed"
    record_manifest "$MANIFEST_KIND_SERVICE" "fstrim.timer" "fstrim.timer" "" ""
}

# ------------------------------------------------- docker (--deep)
check_docker() {
    [[ "$DEEP" -eq 1 ]] || { SKIP_REASON="requires --deep"; return 1; }
    is_scope system || { SKIP_REASON="system-scope op"; return 1; }
    command -v docker >/dev/null && return 0
    SKIP_REASON="docker not installed"; return 1
}
apply_docker() {
    check_docker || return 0
    plan "Pruning docker build cache and dangling images"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    if [[ "$ASSUME_YES" -ne 1 ]]; then
        read -r -p 'Remove docker build cache and dangling images? [y/N] ' ans
        [[ "$ans" =~ ^[Yy]$ ]] || { warn "docker prune skipped"; return 0; }
    fi
    local before after
    before="$(fsize /var/lib/docker)"
    docker builder prune -af >/dev/null 2>&1 || warn "docker builder prune failed"
    docker image prune -f >/dev/null 2>&1 || warn "docker image prune failed"
    after="$(fsize /var/lib/docker)"
    record_freed $((before > after ? before - after : 0))
}

# ------------------------------------------------ repo deps (--deep)
check_repo_deps() {
    [[ "$DEEP" -eq 1 ]] || { SKIP_REASON="requires --deep"; return 1; }
    is_scope user || { SKIP_REASON="user-scope op"; return 1; }
    return 0
}
apply_repo_deps() {
    check_repo_deps || return 0
    # Idle repos: no commits in >30 days.
    [[ -d "${USER_HOME}/dev/github" ]] || return 0
    local list=()
    for repo in "${USER_HOME}"/dev/github/*/; do
        [[ -d "$repo/.git" ]] || continue
        local last
        last="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
        if [[ "$last" -eq 0 ]]; then continue; fi
        local now
        now="$(date +%s)"
        if [[ $((now - last)) -gt $((30 * 86400)) ]]; then
            [[ -d "$repo/node_modules" || -d "$repo/.next" || -d "$repo/.venv" ]] && list+=("$(basename "$repo")")
        fi
    done
    if [[ ${#list[@]} -eq 0 ]]; then skip "repo-deps: no idle repos with build deps"; return 0; fi
    plan "Idle repos (>30d) with build deps: ${list[*]}"
    plan "Would remove node_modules/.next/.venv (deps only; code and .git untouched)"
    if [[ "$MODE" != "--apply" ]]; then return 0; fi
    if [[ "$ASSUME_YES" -ne 1 ]]; then
        read -r -p 'Remove build deps from these idle repos? [y/N] ' ans
        [[ "$ans" =~ ^[Yy]$ ]] || { warn "repo-deps skipped"; return 0; }
    fi
    for repo in "${USER_HOME}"/dev/github/*/; do
        [[ -d "$repo/.git" ]] || continue
        local last now
        last="$(git -C "$repo" log -1 --format=%ct 2>/dev/null || echo 0)"
        now="$(date +%s)"
        [[ $((now - last)) -gt $((30 * 86400)) ]] || continue
        local sz=0 d
        for d in node_modules .next .venv; do
            [[ -d "$repo/$d" ]] && sz=$((sz + $(fsize "$repo/$d")))
        done
        run_as_user rm -rf "$repo/node_modules" "$repo/.next" "$repo/.venv" 2>/dev/null || true
        record_freed "$sz"
    done
}

##############################################################################
# Runner
##############################################################################

declare -a OPS

OPS=(
    apply_repo_deps
    apply_docker
    apply_user_caches
    apply_baloo
    apply_inotify
    apply_dnf5_speed
    apply_dnf_clean
    apply_coredumps
    apply_rotated_logs
    apply_vacuum_journal
    apply_journal_dropin
    apply_fstrim
)

run_op() {
    local fn="$1" check_fn="${1/apply/check}" rc=0
    if [[ "$MODE" == "--apply" ]] && [[ "$IS_ROOT" -eq 0 ]]; then
        # unprivileged apply: only user-scope ops allowed
        if ! is_scope user; then
            warn "SKIP (needs root): $(echo "$fn" | sed 's/apply_//')"
            return 0
        fi
    fi
    if ! "$check_fn"; then
        skip "$(echo "$fn" | sed 's/apply_//') (${SKIP_REASON:-no change needed})"
        SKIP_REASON=""
        return 0
    fi
    SKIP_REASON=""
    # Per-op isolation: errors inside an op must never abort the session.
    if [[ "$MODE" == "--apply" ]]; then
        set +eE
        "$fn"
        rc=$?
        set -eE
        [[ "$rc" -eq 0 ]] || warn "op finished with errors: $fn"
    else
        "$fn"
    fi
}

main() {
    # --- argument parsing
    local rollback_ts=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)         MODE="--dry-run" ;;
            --apply)           MODE="--apply" ;;
            --list-backups)    MODE="--list-backups" ;;
            --rollback)        MODE="--rollback"; rollback_ts="${2:-}"; shift ;;
            --scope)           SCOPE="${2:-all}"; shift ;;
            --deep)            DEEP=1 ;;
            -y|--yes)          ASSUME_YES=1 ;;
            -h|--help)         usage; exit 0 ;;
            *)                 usage; exit 2 ;;
        esac
        shift
    done
    MODE="${MODE:---dry-run}"
    [[ "$SCOPE" =~ ^(user|system|all)$ ]] || fail "--scope must be user|system|all"

    # --- laptop/floor: lock
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then fail "Another instance is running (lock: $LOCK_FILE)."; fi

    case "$MODE" in
        --list-backups)
            configure_root_for_backups
            list_backups
            exit 0
            ;;
        --rollback)
            [[ "$IS_ROOT" -eq 1 ]] || fail "Rollback requires root (backs up under $BACKUP_ROOT)."
            configure_root_for_backups
            rollback "$rollback_ts"
            exit 0
            ;;
    esac

    # dry-run / apply
    if [[ "$MODE" == "--apply" ]]; then
        write_backup_setup_metadata
        say "Optimizing system as user '${REAL_USER}' (scope=${SCOPE})"
    else
        echo
        echo "=== DRY RUN (no changes will be made) ==="
    fi

    for op in "${OPS[@]}"; do
        if [[ "$MODE" == "--apply" ]]; then say "-> $(echo "$op" | sed 's/apply_//')"; fi
        run_op "$op" || warn "op failed: $op"
    done

    if [[ "$MODE" == "--apply" ]]; then
        cleanup_old_backups
        echo
        echo "============================================"
        echo " Summary"
        echo "============================================"
        echo "Backup set : $BACKUP_DIR"
        echo "Space freed: $(human "${FREED_TOTAL}")"
        echo "SELinux    : $(getenforce)"
        echo "TRIM       : $(systemctl is-enabled fstrim.timer)"
        echo "Journal use: $(journalctl --disk-usage 2>/dev/null | tail -1 | sed 's/.*takes up //')"
        echo "============================================"
    else
        echo
        echo "=== DRY RUN COMPLETE (nothing changed) ==="
    fi
    log_to_file "MODE=$MODE scope=$SCOPE deep=$DEEP -> done"
}

# --list-backups / --rollback are read operations over the backup root;
# ensure the root exists for metadata listing if absent.
configure_root_for_backups() {
    if [[ "$IS_ROOT" -eq 1 ]]; then
        mkdir -p "$BACKUP_ROOT"
    fi
}

# NOTE: no global ERR trap here. Per-op error isolation runs inside run_op
# within an error-resilient subshell so one bad op can't abort the run.

main "$@"