#!/bin/bash
# Tests for --append-runbook output on check-security-scan-outcome.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

fail() { echo "FAIL: $1"; exit 1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/append-runbook-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

out="$tmp/runbook.md"

# Running with --append-runbook must append a timestamped section to the file
# and exit 0. Currently the script exits 3 without appending, so this test
# fails until the append behavior is implemented.
bash "$PROJECT_ROOT/spectre/actions/maintenance/check-security-scan-outcome.sh" \
    --append-runbook "$out" || fail "script did not exit 0"

[ -s "$out" ] || fail "runbook file is empty"
grep -q "## security-scan outcome" "$out" || fail "missing outcome header in $out"
grep -q "== security-scan timer/service ==" "$out" || fail "missing timer section in $out"
grep -q "== journal " "$out" || fail "missing journal section in $out"
grep -q "== actions verify ==" "$out" || fail "missing verify section in $out"

echo "PASS: append-runbook creates runbook entry"
