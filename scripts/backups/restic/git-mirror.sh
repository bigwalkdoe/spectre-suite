#!/bin/bash
# Mirror every git repository under a source tree into one directory, so the
# backup can protect history without protecting working trees.
#
# Why this exists
# ---------------
# ~/dev is ~20G, but exclude.conf already drops node_modules, .venv,
# dist and build, so only ~4.3G of it ever reached the backup. The .git
# directories account for just ~342M of that. So the working trees were being
# copied to save history that the .git dirs already contain.
#
# That matters because history is the irreplaceable part. Working trees are
# re-cloneable; commits are not. At the time this was written,
# spectre-system-maintenance-suite had two commits that existed on no remote --
# a `git clone` of any repo here would have silently lost them.
#
# The offsite leg already excludes ~/dev entirely, on the reasoning
# that every repo is on GitHub. This script covers the gap that reasoning
# leaves: commits that are not on GitHub yet.
#
# Usage: git-mirror.sh [--src DIR] [--dest DIR]
#
# Safe to run repeatedly: existing mirrors are fetched, not re-cloned.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_ROOT="${GIT_MIRROR_SRC:-$HOME/dev}"
DEST="${GIT_MIRROR_DEST:-$HOME/.git-mirror}"

QUIET=false
DEBUG=false
while [ $# -gt 0 ]; do
    case "$1" in
        --src)  SRC_ROOT="$2"; shift 2 ;;
        --dest) DEST="$2";    shift 2 ;;
        --quiet) QUIET=true; shift ;;
        --debug|--trace) DEBUG=true; shift ;;
        --version)
            if git -C "$PROJECT_DIR" describe --tags --always >/dev/null 2>&1; then
                echo "git-mirror $(git -C "$PROJECT_DIR" describe --tags --always 2>/dev/null)"
            else
                echo "git-mirror (dev)"
            fi
            exit 0 ;;
        -h|--help)
            sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *)
            printf 'git-mirror.sh: unknown argument: %s\n' "$1" >&2
            exit 2 ;;
    esac
done
if [ "$DEBUG" = true ]; then set -x; fi

if [ ! -d "$SRC_ROOT" ]; then
    printf 'git-mirror: no source dir at %s — nothing to mirror\n' "$SRC_ROOT" >&2
    exit 0
fi

mkdir -p "$DEST"

# Prints exactly one line per repository, or nothing. A repo whose .git is a
# file rather than a directory (worktree, submodule) is skipped: it has no
# independent object store to mirror, and its real repository is discovered
# separately.
find_repos() {
    find "$SRC_ROOT" -maxdepth 4 -name .git -type d -print0 2>/dev/null \
        | while IFS= read -r -d '' dotgit; do
            dirname "$dotgit"
        done
}

# Collapses the path below SRC_ROOT into a flat, unambiguous name. Slashes
# become "__" so two repos cannot collide by sharing a basename, which
# experiments/test and github/test would otherwise do.
slug_for() {
    printf '%s' "${1#"$SRC_ROOT"/}" | tr '/' '_' | tr -c 'A-Za-z0-9._-' '_'
}

mirrored=0
refreshed=0
skipped=0
failed=0

while IFS= read -r repo; do
    [ -n "$repo" ] || continue

    # A repo mid-rebase or mid-clone has no consistent object store to copy.
    if [ -e "$repo/.git/MERGE_HEAD" ] || [ -d "$repo/.git/rebase-merge" ] \
       || [ -d "$repo/.git/rebase-apply" ] || [ -e "$repo/.git/index.lock" ]; then
        printf 'skip (in progress): %s\n' "$repo" >&2
        skipped=$((skipped + 1))
        continue
    fi

    name="$(slug_for "$repo")"
    dest="$DEST/$name.git"

    if [ -d "$dest" ]; then
        # Fetch rather than re-clone so repeated runs cost a ref update instead
        # of recopying every object. '+refs/*:refs/*' mirrors all refs, which
        # is what keeps local-only branches (the unpushed commits) in the copy.
        if git -C "$dest" fetch --prune --quiet origin '+refs/*:refs/*' 2>/dev/null; then
            refreshed=$((refreshed + 1))
        else
            printf 'refresh failed, re-cloning: %s\n' "$repo" >&2
            rm -rf "$dest"
            if git clone --mirror --quiet "$repo" "$dest" 2>/dev/null; then
                mirrored=$((mirrored + 1))
            else
                printf 'FAILED: %s\n' "$repo" >&2
                failed=$((failed + 1))
            fi
        fi
    elif git clone --mirror --quiet "$repo" "$dest" 2>/dev/null; then
        mirrored=$((mirrored + 1))
    else
        printf 'FAILED: %s\n' "$repo" >&2
        failed=$((failed + 1))
    fi
done < <(find_repos)

# Repositories deleted from the source leave a stale mirror behind, which would
# otherwise be backed up forever. Only prune when nothing failed this run, so a
# transient git error cannot cause history to be deleted.
if [ "$failed" -eq 0 ]; then
    live_names=$(mktemp)
    live_count=0
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        slug_for "$r"
        printf '.git\n'
        live_count=$((live_count + 1))
    done < <(find_repos) > "$live_names"
    # Only prune when the source actually yielded repositories. An empty
    # source tree (or a find failure) must never wipe existing mirrors.
    if [ "$live_count" -gt 0 ]; then
        for d in "$DEST"/*.git; do
            [ -d "$d" ] || continue
            base=$(basename "$d")
            if ! grep -qxF "$base" "$live_names"; then
                printf 'removing stale mirror: %s\n' "$base" >&2
                rm -rf "$d"
            fi
        done
    fi
    rm -f "$live_names"
fi

if [ "${QUIET:-false}" != true ]; then
    printf 'git mirror: %d cloned, %d refreshed, %d skipped, %d failed -> %s\n' \
        "$mirrored" "$refreshed" "$skipped" "$failed" "$DEST"
fi

# Non-zero exit only on real failures. Skipped repositories are reported but do
# not fail the run: the mirror is still consistent for everything else, and the
# backup should proceed rather than skip protecting history over one repo that
# happens to be mid-rebase.
[ "$failed" -eq 0 ]
