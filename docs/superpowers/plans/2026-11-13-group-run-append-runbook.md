# Group Run + Append-Runbook Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement two declared-but-not-built features: `spectre run <group>` executes all jobs in a registry group sequentially (stop on first failure, one provenance record per job), and `check-security-scan-outcome.sh --append-runbook <path>` appends the scan outcome to a runbook file.

**Architecture:** Two independent changes in separate code areas. Task 1 adds a `run_group()` function to `spectre/cli/dispatch_cmds.py` that iterates `registry.jobs_in_group()`, calls the existing `run_action_job()` per job, stops on first failure, and exits non-zero if any job failed — wired into the `run` command so group names execute instead of declining. Task 2 modifies `check-security-scan-outcome.sh` to capture its three output blocks and append them as a `## security-scan outcome <timestamp>` markdown section to `--append-runbook <path>` when the flag is given.

**Tech Stack:** Bash, Python 3.11+, typer/click, existing `spectre.dispatch` registry/runner/envelope modules.

**Spec:** `docs/superpowers/specs/2026-11-13-group-run-append-runbook-design.md`

## Global Constraints

- `spectre run` dispatches one target at a time; group execution iterates jobs via `registry.jobs_in_group()` (already returns jobs sorted by name).
- `run_action_job(job, args)` already handles privilege refusal, resolution, locking, run recording, and exit codes — reuse it per job.
- 45 of 61 jobs are `mutates=true` — stop-on-first-failure limits blast radius.
- `--append-runbook` is append-only; never overwrites or clobbers existing runbook content; creates the file if absent.
- `check-security-scan-outcome.sh` remains read-only except for the appended file.
- No changes to `registry_data.json`; `spectre actions verify` must remain clean.

## Review Focus

These input classes/failure modes are implied by the spec but not all pinned by a single task's tests; each is owned by a task:

1. **Group name that is also a job name** (8 of 16 groups collide) — `spectre run <name>` runs the job, not the group; `_note_group_collision` already handles this and must not be broken.
2. **Group with zero jobs** — `run_group` must handle an empty group gracefully (report and exit 0 or a clear refusal).
3. **Job failure mid-group** — stop on first failure, exit non-zero, do not run remaining jobs.
4. **`--append-runbook` with unwritable path** — exit non-zero with a clear error, do not crash.
5. **`--append-runbook` when all commands produce no output** — still write the timestamped header section; do not create an empty file.

---

### Task 1: Group execution — write failing test

**Files:**
- Test: `tests/agent/dispatch/test_group_run.py` (create)

**Interfaces:**
- Consumes: none (pure test setup)
- Produces: a test module that imports `spectre.cli.dispatch_cmds` and `spectre.dispatch.registry`, asserts `run_group` behavior.

- [x] **Step 1: Write the failing test**

```python
def test_run_group_runs_all_jobs_stops_on_failure():
    # Build a tiny in-memory registry or monkeypatch registry.JOBS with two jobs:
    # job A (exit 0) and job B (exit non-zero), plus a third job C that must not run.
    # Call dispatch_cmds.run_group("test-group") and assert:
    #   - run_action_job was called for A and B
    #   - run_action_job was NOT called for C
    #   - exit code is non-zero
```

Expected: FAIL — `run_group` does not exist yet.

- [x] **Step 2: Run test to verify it fails**

Run: `python3 -m pytest tests/agent/dispatch/test_group_run.py -v`
Expected: ImportError / AttributeError for `run_group`.

- [x] **Step 3: Commit**

```bash
git add tests/agent/dispatch/test_group_run.py
git commit -m "test(dispatch): add failing group-run tests"
```

---

### Task 2: Group execution — implement `run_group`

**Files:**
- Modify: `spectre/cli/dispatch_cmds.py`

**Interfaces:**
- Consumes: `registry.jobs_in_group(name) -> list[Job]`, existing `run_action_job(job, args)`.
- Produces: `run_group(name: str) -> int` — runs jobs sequentially, stops on first failure, returns non-zero exit code if any job failed, 0 otherwise.

- [x] **Step 1: Implement `run_group` in dispatch_cmds.py**

Add after `run_action_job`:

```python
def run_group(name: str, args: list[str]) -> int:
    """Run every job in `name` sequentially, stop on first failure.

    Returns 0 if all jobs succeeded, non-zero exit code of the first failed job
    otherwise. One provenance record is written per job via run_action_job.
    """
    members = registry.jobs_in_group(name)
    if not members:
        typer.echo(f"'{name}' is an empty group — nothing to run.")
        return EXIT_OK
    for job in members:
        typer.echo(f"== {job.name} ==")
        run_action_job(job, list(args))
        # run_action_job raises typer.Exit on failure; catch and return its code.
    return EXIT_OK
```

Wait — `run_action_job` raises `typer.Exit` on failure rather than returning a code. I need to catch it:

```python
def run_group(name: str, args: list[str]) -> int:
    members = registry.jobs_in_group(name)
    if not members:
        typer.echo(f"'{name}' is an empty group — nothing to run.")
        return EXIT_OK
    for job in members:
        typer.echo(f"== {job.name} ==")
        try:
            run_action_job(job, list(args))
        except typer.Exit as e:
            return e.exit_code
    return EXIT_OK
```

- [x] **Step 2: Run test to verify it passes**

Run: `python3 -m pytest tests/agent/dispatch/test_group_run.py -v`
Expected: PASS.

- [x] **Step 3: Commit**

```bash
git add spectre/cli/dispatch_cmds.py
git commit -m "feat(dispatch): implement spectre run <group> sequential execution"
```

---

### Task 3: Wire group execution into the `run` command

**Files:**
- Modify: `spectre/cli/dispatch_cmds.py`

**Interfaces:**
- Consumes: `run_group(name, args)` from Task 2.
- Produces: the `run` command calls `run_group` when `_job_lookup` determines `name` is a group.

- [x] **Step 1: Modify the `run` command to route groups to `run_group`**

In the `run` command body (around line 723), replace:

```python
run_action_job(_job_lookup(job), list(args or []))
```

with logic that first checks `registry.groups()`:

```python
if job in registry.groups():
    raise typer.Exit(run_group(job, list(args or [])))
run_action_job(_job_lookup(job), list(args or []))
```

- [x] **Step 2: Run group tests + existing dispatch tests**

Run: `python3 -m pytest tests/agent/dispatch/ -v`
Expected: all dispatch tests pass, including group-run tests.

- [x] **Step 3: Commit**

```bash
git add spectre/cli/dispatch_cmds.py
git commit -m "feat(dispatch): wire spectre run <group> into the run command"
```

---

### Task 4: Append-runbook — write failing test

**Files:**
- Test: `tests/test_append_runbook.sh` (create)

**Interfaces:**
- Consumes: none (shell script under test)
- Produces: a shell test that runs `check-security-scan-outcome.sh --append-runbook <tmpfile>` in a temp environment and asserts:
  - The file exists and is non-empty
  - The file contains a `## security-scan outcome` header
  - The file contains the three section headers (`== security-scan timer/service ==`, `== journal ... ==`, `== actions verify ==`)
  - Exit code is 0

- [x] **Step 1: Write the failing test**

```bash
#!/bin/bash
set -euo pipefail
tmp="$(mktemp -d)"
out="$tmp/runbook.md"
bash spectre/actions/maintenance/check-security-scan-outcome.sh --append-runbook "$out"
[ -s "$out" ] || fail "runbook file is empty"
grep -q "## security-scan outcome" "$out" || fail "missing outcome header"
[ "$?" -eq 0 ] || fail "script did not exit 0"
```

Expected: FAIL — script exits 3 with "append not implemented".

- [x] **Step 2: Run test to verify it fails**

Run: `bash tests/test_append_runbook.sh`
Expected: FAIL (exit 3).

- [x] **Step 3: Commit**

```bash
git add tests/test_append_runbook.sh
git commit -m "test(dashboard-actions): add failing append-runbook test"
```

---

### Task 5: Append-runbook — implement capture + append

**Files:**
- Modify: `spectre/actions/maintenance/check-security-scan-outcome.sh`

**Interfaces:**
- Consumes: `$APPEND` path, `$SINCE`, `$UNTIL` (already set).
- Produces: appends timestamped markdown section to `$APPEND`, exits 0.

- [x] **Step 1: Implement capture and append in check-security-scan-outcome.sh**

Restructure the script so the three output blocks are captured into a variable, printed to stdout, and (when `$APPEND` is set) appended to `$APPEND`:

```bash
OUT=""
capture() {
  # print to stdout and accumulate
  "$@" 2>&1 | tee -a >(cat >> "$OUT_FILE")  # too clever; simpler:
}
```

Simpler approach — use a temp file for capture, then cat to both stdout and $APPEND:

```bash
CAPTURE="$(mktemp)"
trap 'rm -f "$CAPTURE"' EXIT

# Replace the three echo blocks with writes to $CAPTURE:
{
  echo "== security-scan timer/service =="
  systemctl list-timers --all --no-pager 2>&1 | grep -E 'security-scan|NEXT' || true
  echo; systemctl status security-scan.service --no-pager -l 2>&1 || true
  echo "== journal $SINCE .. $UNTIL =="
  journalctl -u security-scan.service --since "$SINCE" --until "$UNTIL" --no-pager 2>&1 || true
  echo "== actions verify =="
  (cd "$ROOT" && python3 -m spectre.cli.main actions verify) 2>&1 | tail -12 || true
} > "$CAPTURE"

cat "$CAPTURE"   # print to stdout

if [ -n "$APPEND" ]; then
  {
    echo
    echo "## security-scan outcome $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo
    cat "$CAPTURE"
  } >> "$APPEND"
fi
```

- [x] **Step 2: Run test to verify it passes**

Run: `bash tests/test_append_runbook.sh`
Expected: PASS (exit 0, file contains header + sections).

- [x] **Step 3: Commit**

```bash
git add spectre/actions/maintenance/check-security-scan-outcome.sh
git commit -m "feat(dashboard-actions): implement --append-runbook output"
```

---

### Task 6: Wire tests into run_tests.sh and run full verification

**Files:**
- Modify: `tests/run_tests.sh`

**Interfaces:**
- Consumes: both new test files.
- Produces: `run_tests.sh` includes the new tests; full suite passes.

- [x] **Step 1: Add new tests to run_tests.sh**

Add:
```bash
run_test_suite "$SCRIPT_DIR/test_append_runbook.sh" "Append-Runbook Tests"
```

And add the pytest dispatch tests — they're already discovered by pytest via `testpaths = ["tests/agent"]`, so no shell change needed for them.

- [x] **Step 2: Run full verification**

Run: `bash tests/run_tests.sh` and `bash tests/test_append_runbook.sh`
Expected: all pass.

- [x] **Step 3: Commit**

```bash
git add tests/run_tests.sh
git commit -m "test(dashboard-actions): wire append-runbook test into run_tests.sh"
```

---

### Task 7: Final whole-branch verification

**Files:**
- Verify: `spectre/cli/dispatch_cmds.py`, `spectre/actions/maintenance/check-security-scan-outcome.sh`, both test files.

**Interfaces:** none

- [x] **Step 1: Run the full shell test suite**

Run: `bash tests/run_tests.sh`
Expected: all 23+ pass.

- [x] **Step 2: Run the agent/dispatch pytest suite**

Run: `python3 -m pytest tests/agent/dispatch/ -v`
Expected: all pass including group-run tests.

- [x] **Step 3: Run `spectre actions verify`**

Run: `python3 -m spectre.cli.main actions verify`
Expected: 90 jobs, 0 findings.

- [x] **Step 4: Manual smoke test of both features**

Run: `python3 -m spectre.cli.main run backups` (a real group) — should execute all backup jobs sequentially and report results.
Run: `bash spectre/actions/maintenance/check-security-scan-outcome.sh --append-runbook /tmp/rb.md` — should exit 0 and write to /tmp/rb.md.

- [x] **Step 5: Commit final state**

```bash
git add spectre/cli/dispatch_cmds.py spectre/actions/maintenance/check-security-scan-outcome.sh tests/
git commit -m "feat: implement group job execution and --append-runbook output"
```

---

**Plan complete and saved to `docs/superpowers/plans/2026-11-13-group-run-append-runbook.md`. Please review the plan. Does it capture what you want?**

**Execution method:** You previously chose **Native**. I'll implement every task myself in this session, with the per-task TDD contract (write failing test, watch it fail, implement, watch it pass, commit).