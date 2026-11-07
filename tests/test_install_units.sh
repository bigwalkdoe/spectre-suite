#!/bin/bash
# Installer §8.2 contract tests (no host mutation)
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
INSTALL="$PROJECT_ROOT/install.sh"

PASSED=0
FAILED=0
pass() { echo "✅ $1"; PASSED=$((PASSED + 1)); }
fail() { echo "❌ $1"; FAILED=$((FAILED + 1)); }

# §8.2: no bulk script install to /usr/local/bin; only spectre wrapper
if grep -qE 'install .*scripts/.* /usr/local/bin/?' "$INSTALL"; then
  fail "install.sh still copies scripts to /usr/local/bin (§8.2 violation)"
else
  pass "install.sh does not copy action scripts to /usr/local/bin"
fi
grep -q '/usr/local/bin/spectre' "$INSTALL" && pass "install.sh installs /usr/local/bin/spectre wrapper" || fail "install.sh does not install /usr/local/bin/spectre"
grep -q 'spectre run' "$INSTALL" && pass "install.sh dispatches jobs via spectre run" || fail "install.sh does not use spectre run"

out=$(USER_NAME=spectre-user SPECTRE_BIN=/usr/local/bin/spectre REPO_ROOT=/repo bash "$INSTALL" --print-units 2>&1) || { fail "--print-units failed"; printf '%s\n' "$out"; echo ""; echo "Installer unit expansion tests: $PASSED passed, $((FAILED+1)) failed"; exit 1; }

for unit in backup maintenance performance-check network-monitor disk-space-check security-scan; do
  block=$(printf '%s\n' "$out" | awk -v h="### ${unit}.service" '$0==h{p=1;next} /^### /{p=0} p{print}')
  if [ -z "$block" ]; then fail "missing generated ${unit}.service"; continue; fi
  printf '%s' "$block" | grep -qF 'User=spectre-user' && printf '%s' "$block" | grep -qF 'Group=spectre-user' \
    && pass "${unit}.service expands User/Group" || fail "${unit}.service missing User/Group expansion"
  printf '%s' "$block" | grep -Eq 'ExecStart=/usr/local/bin/spectre run [a-z0-9_./-]+' \
    && pass "${unit}.service dispatches via spectre run" || fail "${unit}.service not dispatching via spectre run"
done

echo ""
echo "Installer unit expansion tests: $PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
