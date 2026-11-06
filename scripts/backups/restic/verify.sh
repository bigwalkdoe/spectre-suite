#!/bin/bash
# Phase 1 forwarder (§8.4, host-unchanged): set repo root, delegate to spectre/actions impl.
_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPECTRE_REPO_ROOT="$(cd "$_SELF_DIR" && while [ ! -d spectre/actions ] && [ "$PWD" != "/" ]; do cd ..; done; pwd)"
export SPECTRE_REPO_ROOT
_TARGET="$SPECTRE_REPO_ROOT/spectre/actions/backups/restic/verify.sh"
if [ "${BASH_SOURCE[0]-$0}" = "${0-}" ]; then exec "$_TARGET" "$@"; else . "$_TARGET"; fi
