# Absorb spectre-security — Phase 1 Complete (fix path + tests + wire)

**Date:** 2026-11-13
**Repo:** spectre-suite
**Parent spec:** `docs/superpowers/specs/2026-11-07-absorb-spectre-security-design.md` (Phase 1: Inventory & compatibility)

## Intent and why

Phase 1 of absorb-spectre-security added `spectre/actions/security/baseline/baseline-runner.sh` and registry entry `security/baseline/run`, but Phase 1 is not genuinely complete: `baseline-runner.sh` has a path bug (`SUITE_ROOT` resolves one directory too high, breaking `POLICY_DIR` and `run-security-hardening.sh` resolution), there are no tests, and it is not wired into `tests/run_tests.sh`.

Phase 1 complete means the adopted baseline runner actually works on this host, is tested, and is part of the suite test suite — before Phase 2 (baseline phase parity: port remaining helpers) begins.

## Goals

1. Fix `SUITE_ROOT` in `baseline-runner.sh` so `POLICY_DIR` resolves to `spectre/policies` and `run-security-hardening.sh` resolves correctly.
2. Add `tests/test_baseline_runner.sh` covering: script runs without error, OPA check passes, registry entry `security/baseline/run` exists, registry job metadata (sudo, mutates, concurrency, schedule_hint) is correct.
3. Wire `tests/test_baseline_runner.sh` into `tests/run_tests.sh`.

## Non-goals

- Phase 2 baseline phase parity (port remaining helpers: hardening, Trivy, Gitleaks, AIDE, Wazuh, SBOM, drift, image scan, alerting) — that is a separate slice.
- OPA unification (canonical contract + adapter migration) — separate slice.
- Host systemd timer installation — requires explicit operator confirmation per host.

## Constraints

- `baseline-runner.sh` must remain non-destructive/additive: does not modify spectre-security or existing jobs.
- `run-security-hardening.sh` requires root (sudo=true); tests must not attempt to run it as non-root.
- Trivy fs scan times out without network access; tests must not depend on trivy downloading a vulnerability DB.
- `spectre actions verify` must remain clean (90 jobs, 0 findings).
- All existing tests must continue to pass.

## Approaches considered

**A) Fix path + add tests + wire into suite** (selected) — Fix `SUITE_ROOT` (`../../../../..` → `../../../..`), add `tests/test_baseline_runner.sh`, wire into `tests/run_tests.sh`. Phase 1 genuinely complete.

**B) Fix path only** — Fix `SUITE_ROOT`, verify script runs, defer tests/wiring. Leaves Phase 1 incomplete (no test coverage, not in test suite).

**D) Declare Phase 1 done as-is** — Leave path bug and lack of tests. Phase 1 not genuinely complete; risk of shipping broken code.

## How it gets built

**`spectre/actions/security/baseline/baseline-runner.sh`:**
- Change `SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../../.." && pwd)}"` to `SUITE_ROOT="${SPECTRE_REPO_ROOT:-$(cd "$SCRIPT_DIR/../../../.." && pwd)}"` so `POLICY_DIR=$SUITE_ROOT/spectre/policies` resolves to the actual `spectre/policies` directory.

**`tests/test_baseline_runner.sh` (new):**
- Test `baseline-runner.sh` runs without error (it exits 0 even with optional phases skipped).
- Test `registry.get_job("security/baseline/run")` returns the expected job with correct `sudo`, `mutates`, `concurrency`, `schedule_hint`.
- Test `OPA check spectre/policies/` passes (suite-native OPA gate remains canonical).

**`tests/run_tests.sh`:**
- Add `run_test_suite "$SCRIPT_DIR/test_baseline_runner.sh" "Baseline Runner Tests"`.

## What's left to the builder

- Exact test assertions for marker/log file contents (the runner writes `baseline.log`, `opa-check.log`, etc. under `LOG_DIR`).
- Whether `spectre actions verify` should be invoked inside the baseline-runner test (it already runs separately in the suite).

## Approval needed

Sign off on this short design (reply yes/no). If approved, I'll write the implementation plan and proceed with implementation on a new branch.