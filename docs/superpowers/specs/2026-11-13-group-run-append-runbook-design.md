# Design: Group Job Execution + Append-Runbook Output

**Date:** 2026-11-13
**Repo:** spectre-suite
**Target:** `spectre/cli/dispatch_cmds.py`, `spectre/actions/maintenance/check-security-scan-outcome.sh`

## Intent and why

Two features declared but not built:

1. **Group job execution** — `spectre run <group-name>` currently reports the group and its size, then declines ("Running a whole group is not implemented"). Operators want to run all jobs in a registry group with one command.
2. **`--append-runbook <path>`** — `check-security-scan-outcome.sh` accepts the flag but exits without appending anything, telling operators to edit manually. Operators want the scan outcome written to a runbook file automatically.

## Goals

1. `spectre run <group>` runs all jobs in the group sequentially, stops on first failure, writes one provenance run record per job, exits non-zero if any job failed.
2. `check-security-scan-outcome.sh --append-runbook <path>` appends a `## security-scan outcome <timestamp>` markdown section with the timer status, journal window, and `actions verify` output to `<path>`, creating the file if needed, exits 0.

## Non-goals

1. Group ordering/dependency semantics (deferred per consolidation design spec — groups run in registry order).
2. Group-level provenance aggregation (one record per job, not one per group).
3. Runbook formatting beyond markdown sections; no JSON or machine-parseable output.
4. No changes to existing single-job `spectre run <job>` behavior.

## Anti-goals

- A group run that silently continues after a job failure without recording it.
- An `--append-runbook` that overwrites instead of appends, or that creates empty files on failure.
- Breaking the `spectre actions verify` gate (registry unchanged).

## Constraints

- `spectre run` takes one target at a time; group execution must iterate jobs via the existing registry API.
- 45 of 61 jobs are `mutates=true` — stop-on-first-failure limits blast radius.
- `--append-runbook` must not clobber existing runbook content; append-only.
- `check-security-scan-outcome.sh` remains read-only except for the appended file.

## Approaches considered

**Feature 1 — Group execution:**
- **A) Sequential, stop-on-first-failure, one run record per job** (selected) — safe blast-radius limit, simple provenance.
- B) Sequential, continue-on-failure, group-level record — more work done but failures can be missed.
- C) Sequential, stop-on-first-failure, group-level record — simpler provenance but hides which job failed.

**Feature 2 — Append-runbook:**
- **A) Append markdown section with header + timer/journal/verify output** (selected) — human-readable, matches existing script output format.
- B) JSON lines — machine-parseable but not operator-readable.
- C) Markdown + embedded JSON — most flexible but more code.

## How it gets built

**`spectre/cli/dispatch_cmds.py`:**
- Add `run_group(name)` that iterates `registry.jobs_in_group(name)`, calls the existing per-job dispatch path for each, stops on first non-zero exit, writes one provenance record per job via the existing `run_record`/`write_run_record` path, exits non-zero on any failure.
- Wire into the existing unknown-job/group-collision flow: when `name` is a group, call `run_group(name)` instead of declining.

**`spectre/actions/maintenance/check-security-scan-outcome.sh`:**
- When `--append-runbook <path>` is given and `$APPEND` is set, append `## security-scan outcome <UTC timestamp>` + the same three output blocks (timer status, journal window, actions verify) to `<path>`, creating the file if absent, then exit 0.
- When `APPEND` is empty, behavior is unchanged (print to stdout, exit 0).

## What's left to the builder

- Exact provenance record format for per-job group runs (matches existing single-job run record schema).
- Whether group output is streamed to stdout as each job runs or buffered (recommend streamed, matching existing job output).

## Approval needed

Sign off on this short design (reply yes/no). If approved, I'll write the implementation plan and proceed.