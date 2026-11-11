#!/bin/bash
# Conservative local backup artifact trimming
#
# Reclaims space from local Spectre-owned backup artifacts without touching
# restic repository internals and without deleting outside configured/owned
# paths and retention bounds.
#
# Actions (conservative):
#   - remove structurally hollow/unusable archives in owned Spectre backup patterns
#   - remove old valid timestamped backup artifacts beyond retention in configured dirs
#   - clean stale dump temp dirs beyond a safe age in the configured dumps path
#
# Structural validation is aligned with check-backup-health.sh: never size-only
# deletion that could remove a valid small backup.
set -uo pipefail

DRY_RUN=0
BACKUP_ARTIFACT_RETENTION_DAYS="${BACKUP_ARTIFACT_RETENTION_DAYS:-30}"
BACKUP_DB_DIR="${BACKUP_DB_DIR:-/backups/databases}"
BACKUP_VOLUME_DIR="${BACKUP_VOLUME_DIR:-/backups/docker-volumes}"
BACKUP_TRIM_STATE_DIR="${BACKUP_TRIM_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/spectre-suite}"
BACKUP_DUMPS_DIR="${BACKUP_DUMPS_DIR:-$BACKUP_TRIM_STATE_DIR/dumps}"
BACKUP_DUMP_STALE_HOURS="${BACKUP_DUMP_STALE_HOURS:-24}"
BACKUP_ARTIFACT_DIRS="${BACKUP_ARTIFACT_DIRS:-}"
# Floor for gzip-of-nothing (~20-30 bytes). Aligned with backup health check.
MIN_ARCHIVE_BYTES="${MIN_ARCHIVE_BYTES:-32}"

usage() {
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--retention-days N]

Conservatively trim local Spectre-owned backup artifacts.

Options:
  --dry-run           Report actions without deleting anything
  --retention-days N  Remove valid owned artifacts older than N days (default: ${BACKUP_ARTIFACT_RETENTION_DAYS})
  -h, --help          Show this help

Environment overrides:
  BACKUP_DB_DIR, BACKUP_VOLUME_DIR       Defaults: /backups/databases, /backups/docker-volumes
  BACKUP_ARTIFACT_DIRS                   Colon/comma/space-separated dirs to scan (overrides DB/VOLUME dirs)
  BACKUP_ARTIFACT_RETENTION_DAYS         Default: 30
  BACKUP_TRIM_STATE_DIR, BACKUP_DUMPS_DIR
  BACKUP_DUMP_STALE_HOURS                Default: 24
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --retention-days)
            if [ -z "${2:-}" ]; then echo "ERROR: --retention-days requires a value" >&2; exit 2; fi
            BACKUP_ARTIFACT_RETENTION_DAYS="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

case "$BACKUP_ARTIFACT_RETENTION_DAYS" in
    ''|*[!0-9]*) echo "ERROR: BACKUP_ARTIFACT_RETENTION_DAYS must be a non-negative integer" >&2; exit 2 ;;
esac
case "$BACKUP_DUMP_STALE_HOURS" in
    ''|*[!0-9]*) echo "ERROR: BACKUP_DUMP_STALE_HOURS must be a non-negative integer" >&2; exit 2 ;;
esac

errors=0
removed_hollow=0
removed_old=0
removed_dumps=0
kept=0
scanned=0
would_remove=0

log() { echo "$*"; }
warn() { echo "WARN: $*" >&2; }
fail() { echo "ERROR: $*" >&2; errors=$((errors + 1)); }

# Structural validation aligned with spectre/actions/backups/check-backup-health.sh
validate_archive() {
    local file="$1"
    case "$file" in
        *.tar.gz|*.tgz)
            tar -tzf "$file" >/dev/null 2>&1 || return 1
            [ -n "$(tar -tzf "$file" 2>/dev/null | head -1)" ] || return 1
            ;;
        *.sql.gz)
            gzip -t "$file" 2>/dev/null || return 1
            gzip -dc "$file" 2>/dev/null | head -20 | grep -q "PostgreSQL database dump" || return 1
            ;;
        *.rdb)
            head -c 5 "$file" 2>/dev/null | grep -q "REDIS" || return 1
            ;;
        *.gz)
            gzip -t "$file" 2>/dev/null || return 1
            ;;
        *)
            return 1
            ;;
    esac
    return 0
}

is_hollow_or_unusable() {
    local file="$1" size
    if [ ! -f "$file" ]; then return 1; fi
    size=$(stat -c %s "$file" 2>/dev/null) || return 1
    if [ "$size" -lt "$MIN_ARCHIVE_BYTES" ]; then
        return 0
    fi
    if ! validate_archive "$file"; then
        return 0
    fi
    return 1
}

remove_path() {
    local path="$1" reason="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY RUN: would remove ($reason): $path"
        would_remove=$((would_remove + 1))
        return 0
    fi
    if rm -f -- "$path"; then
        log "removed ($reason): $path"
        return 0
    else
        fail "could not remove $path"
        return 1
    fi
}

remove_dir() {
    local path="$1" reason="$2"
    if [ "$DRY_RUN" -eq 1 ]; then
        log "DRY RUN: would remove dir ($reason): $path"
        would_remove=$((would_remove + 1))
        return 0
    fi
    if rm -rf -- "$path"; then
        log "removed dir ($reason): $path"
        return 0
    else
        fail "could not remove directory $path"
        return 1
    fi
}

# Owned Spectre backup artifact patterns (conservative, explicit)
# Args: dir
trim_in_dir() {
    local dir="$1"
    [ -d "$dir" ] || return 0

    local -a patterns=(
        "postgres_*.sql.gz"
        "redis_backup_*.rdb"
        "neo4j_dump_*.tar.gz"
        "mongodb_dump_*.tar.gz"
        "spectre-suite_*.tar.gz"
    )
    local pattern f mtime now age_days
    now=$(date +%s)

    for pattern in "${patterns[@]}"; do
        while IFS= read -r -d '' f; do
            [ -f "$f" ] || continue
            scanned=$((scanned + 1))
            if is_hollow_or_unusable "$f"; then
                if remove_path "$f" "hollow/unusable"; then
                    [ "$DRY_RUN" -eq 0 ] && removed_hollow=$((removed_hollow + 1))
                fi
                continue
            fi
            # Valid artifact: age-based retention
            mtime=$(stat -c %Y "$f" 2>/dev/null) || { fail "cannot stat $f"; continue; }
            age_days=$(( (now - mtime) / 86400 ))
            if [ "$age_days" -gt "$BACKUP_ARTIFACT_RETENTION_DAYS" ]; then
                if remove_path "$f" "older than ${BACKUP_ARTIFACT_RETENTION_DAYS}d (${age_days}d)"; then
                    [ "$DRY_RUN" -eq 0 ] && removed_old=$((removed_old + 1))
                fi
            else
                kept=$((kept + 1))
            fi
        done < <(find "$dir" -maxdepth 1 -type f -name "$pattern" -print0 2>/dev/null)
    done
}

# Build list of dirs to scan
declare -a scan_dirs=()
if [ -n "$BACKUP_ARTIFACT_DIRS" ]; then
    IFS=':,' read -r -a _parts <<< "$BACKUP_ARTIFACT_DIRS"
    for p in "${_parts[@]}"; do
        # trim whitespace
        p="${p#"${p%%[![:space:]]*}"}"
        p="${p%"${p##*[![:space:]]}"}"
        [ -n "$p" ] && scan_dirs+=("$p")
    done
    # also allow space-separated if no separators produced multiple
    if [ "${#scan_dirs[@]}" -le 1 ] && [[ "$BACKUP_ARTIFACT_DIRS" == *" "* ]]; then
        scan_dirs=()
        # shellcheck disable=SC2206
        scan_dirs=( $BACKUP_ARTIFACT_DIRS )
    fi
else
    scan_dirs=("$BACKUP_DB_DIR" "$BACKUP_VOLUME_DIR")
fi

log "Backup artifact trim"
log "  dry-run          : $([ "$DRY_RUN" -eq 1 ] && echo yes || echo no)"
log "  retention days   : $BACKUP_ARTIFACT_RETENTION_DAYS"
log "  dump stale hours : $BACKUP_DUMP_STALE_HOURS"
log "  scan dirs        : ${scan_dirs[*]:-<none>}"
log "  dumps dir        : $BACKUP_DUMPS_DIR"
log ""

for d in "${scan_dirs[@]}"; do
    if [ ! -d "$d" ]; then
        log "  skip (missing dir): $d"
        continue
    fi
    trim_in_dir "$d"
done

# Stale dump temp dir cleanup (only inside configured dumps dir)
if [ -d "$BACKUP_DUMPS_DIR" ]; then
    stale_minutes=$((BACKUP_DUMP_STALE_HOURS * 60))
    while IFS= read -r -d '' dd; do
        [ -d "$dd" ] || continue
        if remove_dir "$dd" "stale dump temp dir (> ${BACKUP_DUMP_STALE_HOURS}h)"; then
            [ "$DRY_RUN" -eq 0 ] && removed_dumps=$((removed_dumps + 1))
        fi
    done < <(find "$BACKUP_DUMPS_DIR" -mindepth 1 -maxdepth 1 -type d -mmin "+${stale_minutes}" -print0 2>/dev/null)
fi

log ""
if [ "$DRY_RUN" -eq 1 ]; then
    log "SUMMARY (dry-run): scanned=$scanned would_remove=$would_remove kept_valid=$kept errors=$errors"
else
    log "SUMMARY: scanned=$scanned removed_hollow=$removed_hollow removed_old=$removed_old removed_stale_dump_dirs=$removed_dumps kept_valid=$kept errors=$errors"
fi

if [ "$errors" -ne 0 ]; then
    exit 1
fi
exit 0
