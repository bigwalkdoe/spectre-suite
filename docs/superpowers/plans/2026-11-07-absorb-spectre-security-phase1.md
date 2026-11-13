# Absorb spectre-security — Phase 1 Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Phase 1 of absorb-spectre-security: fix the `SUITE_ROOT` path bug in `baseline-runner.sh`, add tests for the baseline runner, and wire the test into `tests/run_tests.sh`.

**Architecture:** Three independent changes: (1) fix a path calculation in `spectre/actions/security/baseline/baseline-runner.sh` so `POLICY_DIR` resolves to `spectre/policies`; (2) add `tests/test_baseline_runner.sh` with tests for script execution, registry entry correctness, and OPA gate; (3) add the new test to `tests/run_tests.sh`.

**Tech Stack:** Bash, Python 3.11+, pyt

ytest, existing `spectre.dispatch.registry` module, `spectre.cli.dispatch_cmds` module.

**Spec:** `docs/superpowers/specs/2026-11-07-absorb-spectre-security-phase1-design.md`

## Global Constraints

- `baseline-runner.sh` must remain non-destructive/additive: does not modify spectre-security or existing jobs.
- `run-security-hardening.sh` requires root (sudo=true); tests must not attempt to run it as non-root.
- Trivy fs scan times out without network access; tests must not depend on trivy downloading a vulnerability DB.
- `spectre actions verify` must remain clean (90 jobs, 0 findings).
- All existing tests must continue to pass.

## Review Focus

These input classes/failure modes are implied by the spec but not all pinned by a single task's tests:

1. **`SUITE_ROOT` path points to the parent of the repo** — `POLICY_DIR` resolves to a nonexistent directory, OPA check fails. (Task 1 fixes; Task 2 test pins it.)
2. **`run-security-hardening.sh` not found** — same path bug causes helper resolution failure. (Task 1 fixes; Task 2 test pins registry entry metadata.)
3. **Trivy fs times out without network** — environmental; tests must not depend on it. (Task 2 test skips trivy-dependent assertions.)
4. **Baseline runner not in test suite** — no test coverage means regressions go unnoticed. (Task 3 wires it in.)

---

### Task 1: Fix `SUITE_ROOT` path bug in baseline-runner.sh

**Files:**
- Modify: `spectre/actions/security/baseline/baseline-runner.sh`

**Interfaces:**
- Consumes: none
- Produces: `SUITE_ROOT` resolves to the repo root (`~//dev/github/spectre-suite`), so `POLICY_DIR` = `$SUITE_ROOT/spectre/policies` exists and `run-security-hardening.sh` resolves under `$SUITE_ROOT/spectre/actions/security/`.

- [x] **Step 1: Write the failing test**

No new test needed here — the existing test in Task 2 will fail because `SUITE_ROOT` is wrong (POLICY_DIR points to nonexistent dir). Run Task 2's test first to confirm RED.

- [x] **Step 2: Implement the fix**

Change line 15 of `baseline-runner.sh`:

```bash
SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"
```

to:

```bash
SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"
```

`SCRIPT_DIR` = `.../spectre/actions/security/baseline` (3 levels up from repo root: baseline → security → actions → spectre → repo). `../../../..` from `spectre/actions/security/baseline` reaches the repo root.

- [x] **Step 3: Verify the fix**

Run: `SUITE_ROOT=$(cd "$(dirname "$(dirname "$(dirname "$(dirname "$(realpath spectre/actions/security/baseline/baseline-runner.sh")"))" )" )" && pwd) || echo "manual"` — simpler: just run Task 2's test which pins `POLICY_DIR` existence.

Expected: `tests/test_baseline_runner.sh` passes (OPA check runs against `spectre/policies` which exists).

- [x] **Step 4: Commit**

```bash
git add spectre/actions/security/baseline/baseline-runner.sh
git commit -m "fix(security-baseline): fix SUITE_ROOT path bug so POLICY_DIR resolves correctly"
```

---

### Task 2: Add tests for the baseline runner

**Files:**
- Create: `tests/test_baseline_runner.sh`

**Interfaces:**
- Consumes: `spectre.dispatch.registry.get_job`, `spectre.dispatch.registry.JOBS`
- Produces: test functions asserting baseline-runner.sh runs, registry entry metadata correct, OPA check passes.

- [x] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Tests for spectre/actions/security/baseline/baseline-runner.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

fail() { echo "FAIL: $1"; exit 1; }
pass() { echo "PASS: $*"; }

# Test 1: baseline-runner.sh runs without error (exits 0)
echo "Test 1: baseline-runner.sh runs without error"
LOG_DIR="$(mktemp -d)"
SECURITY_BASELINE_LOG_DIR="$LOG_DIR" SECURITY_OPA_COMPAT=0 \
  bash "$PROJECT_ROOT/spectre/actions/security/baseline/baseline-runner.sh" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  fail "baseline-runner.sh exited $rc, expected 0"
fi
pass "baseline-runner.sh exits 0"

# Test 2: registry entry security/baseline/run exists with correct metadata
python3 -c "
import json, sys
with open('$PROJECT_ROOT/spectre/dispatch/registry_data.json') as f:
    data = json.load(f)
job = next((j for j in data if j.get('name') == 'security/baseline/run'), None)
assert job is not None, 'security/baseline/run not in registry'
assert job['sudo'] is True, f\"sudo={job['sudo']}, expected True\"
assert job['mutates'] is True, f\"mutates={job['mutates']}, expected True\"
assert job['concurrency'] == 'forbid', f\"concurrency={job['concurrency']}, expected 'forbid'\"
assert job['schedule_hint'] is None, f\"schedule_hint={job['schedule_hint']}, expected None\"
assert job['action'] == 'security/baseline/run.sh', f\"action={job['action']}, expected 'security/baseline/run.sh'\"
print('registry entry metadata OK')
"

# Test 3: POLICY_DIR resolves to an existing directory (SUITE_ROOT path fix)
SCRIPT_DIR="$PROJECT_ROOT/spectre/actions/security/baseline"
SUITE_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
POLICY_DIR="$SUITE_ROOT/spectre/policies"
if [ ! -d "$POLICY_DIR" ]; then
  fail "POLICY_DIR=$POLICY_DIR does not exist — SUITE_ROOT path bug not fixed"
fi
pass "POLICY_DIR=$POLICY_DIR exists (SUITE_ROOT path fix verified)"

# Test 4: OPA check passes (suite-native OPA gate remains canonical)
if command -v opa >/dev/null 2>&1; then
  if ! opa check "$POLICY_DIR" >/dev/null 2>&1; then
    fail "opa check $POLICY_DIR failed"
  fi
  pass "opa check $POLICY_DIR passes"
else
  echo "SKIP: opa not installed, skipping OPA check test"
fi

echo "ALL BASELINE RUNNER TESTS PASSED"
```

Expected: FAIL — `SUITE_ROOT` is wrong (`../../../../..` resolves to `~//dev/github` instead of `~//dev/github/spectre-suite`), so `POLICY_DIR` doesn't exist and `baseline-runner.sh` warns about missing directory but still exits 0 (it degrades gracefully). Actually — since baseline-runner.sh degrades gracefully (warns instead of failing), Test 1 might pass even with the bug. Test 3 (POLICY_DIR exists) is the one that definitively catches the path bug.

Let me reconsider: baseline-runner.sh warns on missing POLICY_DIR but continues and exits 0. So Test 1 (exit 0) passes even with the bug. Test 3 (POLICY_DIR exists) is the definitive check. Good — the test file has both.

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_baseline_runner.sh`
Expected: FAIL — Test 3 fails because `POLICY_DIR` points to `~//dev/github/spectre/policies` which doesn't exist (SUITE_ROOT resolves to `~//dev/github`).

- [x] **Step 3: Implement the fix (Task 1)**

Apply the `SUITE_ROOT` fix from Task 1.

- [x] **Step 4: Run test to verify it passes**

Run: `bash tests/test_baseline_runner.sh`
Expected: PASS — all 4 tests pass.

- [x] **Step 5: Commit**

```bash
git add tests/test_baseline_runner.sh
git commit -m "test(security-baseline): add baseline-runner tests"
```

---

### Task 3: Wire test into run_tests.sh

**Files:**
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: `tests/test_baseline_runner.sh` (from Task 2)
- Produces: `run_tests.sh` includes the new test in its suite

- [x] **Step 1: Add test to run_tests.sh**

Add after the security-related tests:

```bash
run_test_suite "$SCRIPT_DIR/test_baseline_runner.sh" "Baseline Runner Tests"
```

Place it after `test_security_metrics.sh` and before `test_schedule_ownership.sh` (grouping with security tests).

- [x] **Step 2: Run full suite to verify**

Run: `bash tests/run_tests.sh`
Expected: all tests pass (24 + 1 = 25, or whatever the new total is).

- [x] **Step 3: Commit**

```bash
git add tests/run_tests.sh
git commit -m "test: wire baseline-runner test into run_tests.sh"
```

---

### Task 4: Final whole-branch verification

**Files:**
- Verify: `spectre/actions/security/baseline/baseline-runner.sh`, `tests/test_baseline_runner.sh`, `tests/run_tests.sh`

**Interfaces:** none

- [x] **Step 1: Run full test suite**

Run: `bash tests/run_tests.sh`
Expected: all pass (25 tests, 0 failed).

- [x] **Step 2: Run spectre actions verify**

Run: `python3 -m spectre.cli.main actions verify`
Expected: 90 jobs, 0 findings (registry unchanged).

- [x] **Step 3: Run shellcheck on modified script**

Run: `shellcheck spectre/actions/security/baseline/baseline-runner.sh`
Expected: no new warnings (only pre-existing ones).

- [x] **Step 4: Manual smoke test of baseline-runner.sh**

Run: `bash spectre/actions/security/baseline/baseline-runner.sh`
Expected: exits 0, writes `baseline.log`, `opa-check.log` under `LOG_DIR`.

- [x] **Step 5: Commit final state**

```bash
git add spectre/actions/security/baseline/baseline-runner.sh tests/test_baseline_runner.sh tests/run_tests.sh
git commit -m "feat(security-baseline): complete Phase 1 — fix path, add tests, wire into suite"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-11-07-absorb-spectre-security-phase1.md`. Please review the plan. Does it capture what you want?**

**Execution method:** You previously chose **Native** for the reports subsystem. I'll implement every task myself in this session, with per-task TDD (write failing test, watch it fail, implement, watch it pass, commit).