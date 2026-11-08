#!/bin/bash
set -euo pipefail

# Projects Backup Script
# Backs up explicitly configured project directories. This is host-specific and
# optional: unconfigured runs skip cleanly so backup-all is not failed by stale
# defaults.

BACKUP_DIR="${BACKUP_DIR:-/backups/projects}"
PROJECTS_ROOT="${PROJECTS_ROOT:-${PROJECTS_DIR:-}}"
DATE=$(date +%Y%m%d_%H%M%S)
RETENTION_DAYS=${RETENTION_DAYS:-14}

mkdir -p "$BACKUP_DIR"

echo "Backing up project directories..."

# BACKUP_PROJECTS: space-separated absolute paths, or names/paths relative to PROJECTS_ROOT.
# Deliberately no hardcoded project names: configure per host.
if [[ -n "${BACKUP_PROJECTS:-}" ]]; then
    # shellcheck disable=SC2206
    requested_projects=($BACKUP_PROJECTS)
elif [[ -n "${PROJECTS_ROOT:-}" && -d "${PROJECTS_ROOT:-}" && -n "${BACKUP_PROJECTS_AUTO_DISCOVER:-}" ]]; then
    # Opt-in discovery only; never guess by default.
    mapfile -t requested_projects < <(find "$PROJECTS_ROOT" -mindepth 1 -maxdepth 1 -type d | sort)
else
    echo "  project backups not configured (set BACKUP_PROJECTS and/or PROJECTS_ROOT); skipping"
    echo "Project backup skipped (not configured): $DATE"
    logger -p user.info "Project backup skipped: not configured" 2>/dev/null || true
    exit 0
fi

failures=0
backed_up=0
for project in "${requested_projects[@]}"; do
    if [[ "$project" != /* ]]; then
        if [[ -z "${PROJECTS_ROOT:-}" ]]; then
            echo "WARNING: skipping relative project '$project' (PROJECTS_ROOT not set)" >&2
            failures=$((failures + 1))
            continue
        fi
        project="$PROJECTS_ROOT/$project"
    fi
    if [[ ! -d "$project" ]]; then
        echo "WARNING: project directory not found, skipping: $project" >&2
        failures=$((failures + 1))
        continue
    fi

    project_name=$(basename "$project")
    parent_dir=$(dirname "$project")
    archive="$BACKUP_DIR/${project_name}_${DATE}.tar.gz"
    echo "Backing up project: $project_name"

    # Exclude build artifacts and secret material so credentials never land in backups.
    if tar czf "$archive" \
        --exclude='node_modules' \
        --exclude='.git' \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.venv' \
        --exclude='venv' \
        --exclude='dist' \
        --exclude='build' \
        --exclude='.next' \
        --exclude='.cache' \
        --exclude='.env' \
        --exclude='.env.*' \
        --exclude='secrets' \
        -C "$parent_dir" "$project_name"; then
        backed_up=$((backed_up + 1))
    else
        echo "ERROR: failed to archive project: $project" >&2
        rm -f "$archive"
        failures=$((failures + 1))
    fi
done

# Cleanup old backups
echo "Cleaning up old project backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -maxdepth 1 -type f -name '*_[0-9][0-9][0-9][0-9]*.tar.gz' -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true

if (( backed_up == 0 && failures > 0 )); then
    echo "Project backup failed: no projects backed up ($failures error(s))" >&2
    exit 1
fi
if (( failures > 0 )); then
    echo "Project backup completed with warnings: $backed_up backed up, $failures failed: $DATE"
    logger -p user.warning "Project backup completed with $failures failure(s)" 2>/dev/null || true
    exit 0
fi

echo "Project backup completed: $backed_up project(s), $DATE"
logger -p user.info "Project backup completed successfully ($backed_up project(s))" 2>/dev/null || true
